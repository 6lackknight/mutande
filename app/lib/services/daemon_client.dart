import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../platform/user_home.dart';

/// Local IPC client for `mutande-core serve`.
///
/// App transport (current): JSON-RPC 2.0 over HTTP POST to
/// `{httpBaseUrl}/rpc` (dev bridge). Daemon-native transport is a Unix domain
/// socket at `~/.mutande/daemon.sock` (`mutande-core serve --socket`); this
/// client does not speak the socket yet — [socketPath] is informational only.
///
/// ## HTTP auth
///
/// The daemon writes a bearer token to [defaultHttpTokenPath]
/// (`~/.mutande/daemon_http_token`, mode `0o600`) when the HTTP bridge starts.
/// Every `POST /rpc` must send `Authorization: Bearer <token>` (or
/// `X-Mutande-Token`). Unix socket IPC stays unauthenticated for local MCP.
///
/// ## JSON-RPC methods (see `core/src/daemon/rpc.rs`)
///
/// | Method | Purpose |
/// |--------|---------|
/// | `health` | Liveness ping; returns `{ ok, service, version? }` |
/// | `get_status` / `me` | signed_in / needs_onboarding / configured + handle |
/// | `auth_login` | Auth0 loopback (or injected token) → persist tokens |
/// | `create_org` | Create team after Auth0 |
/// | `join_org` / `onboard` | Join via invite after Auth0 |
/// | `list_contacts` | Org members + synthetic `@all@org` |
/// | `list_threads` | Filter: omit/`null` = all; `needs_action`, `open`, `closed` |
/// | `get_thread` | Thread + messages with decrypted `bundle` (or `open_error` without ciphertext) |
/// | `get_draft` | Current self-draft (plain after hub sync) |
/// | `draft_add_question` | Merge human decision into draft |
/// | `draft_add_resource` | Merge resource request into draft |
/// | `forward_draft` | Send draft to recipient; opens thread |
/// | `reply_to_thread` | Encrypted reply on existing thread |
/// | `close_thread` | Mark thread closed |
/// | `delete_thread` | Remove from inbox (sender purges body) |
/// | `mark_processed` | Clear local pending / processed flags |
/// | `connect_host` | Write MCP configs (`host`: cursor\|claude\|chatgpt\|all) |
///
/// MCP tools forward to the same daemon surface via `mutande-core mcp` stdio —
/// not called directly from Flutter.
class DaemonClient {
  DaemonClient({
    http.Client? httpClient,
    this.httpBaseUrl = defaultHttpBaseUrl,
    this.socketPath = defaultSocketPath,
    this.httpTokenPath = defaultHttpTokenPath,
    String? httpToken,
    // Hub RPCs + Keychain bootstrap routinely exceed a few seconds on first open.
    this.requestTimeout = const Duration(seconds: 15),
  })  : _http = httpClient ?? http.Client(),
        _httpTokenOverride = httpToken;

  /// Dev HTTP bridge (current Flutter transport).
  static const defaultHttpBaseUrl = 'http://127.0.0.1:3847';

  /// Daemon-native socket path (not used by this HTTP client yet).
  static const defaultSocketPath = '~/.mutande/daemon.sock';

  /// Token file written by `mutande-core serve` for the HTTP bridge.
  static const defaultHttpTokenPath = '~/.mutande/daemon_http_token';

  final http.Client _http;
  final String httpBaseUrl;
  final String socketPath;
  final String httpTokenPath;
  final String? _httpTokenOverride;
  final Duration requestTimeout;

  int _jsonRpcId = 0;
  String? _cachedHttpToken;

  /// Session status via JSON-RPC `get_status` (alias `me`).
  ///
  /// Longer than [requestTimeout]: the daemon may call hub `/me` (network RTT).
  Future<DaemonStatusResult> getStatus() async {
    final result = await _callWithTimeout(
      'get_status',
      null,
      const Duration(seconds: 15),
    );
    final map = result as Map<String, dynamic>? ?? {};
    return DaemonStatusResult.fromJson(map);
  }

  /// Auth0 login via daemon loopback OAuth (or injected [accessToken] for tests).
  ///
  /// Opens the system browser; returns status (`signed_in` / `needs_onboarding`).
  Future<DaemonStatusResult> authLogin({
    required String hubUrl,
    String? auth0Domain,
    String? auth0ClientId,
    String? auth0Audience,
    String? accessToken,
    String? refreshToken,
    bool openBrowser = true,
  }) async {
    final params = <String, dynamic>{
      'hub_url': hubUrl,
      'open_browser': openBrowser,
    };
    if (auth0Domain != null) params['auth0_domain'] = auth0Domain;
    if (auth0ClientId != null) params['auth0_client_id'] = auth0ClientId;
    if (auth0Audience != null) params['auth0_audience'] = auth0Audience;
    if (accessToken != null) params['access_token'] = accessToken;
    if (refreshToken != null) params['refresh_token'] = refreshToken;
    // OAuth can take minutes; daemon keeps the loopback socket for 5 minutes.
    final result = await _callWithTimeout(
      'auth_login',
      params,
      const Duration(minutes: 5),
    );
    final map = result as Map<String, dynamic>? ?? {};
    return DaemonStatusResult.fromJson(map);
  }

  /// Create team after Auth0 (`POST /v1/orgs` via daemon).
  Future<OnboardResult> createOrg({
    required String slug,
    String? name,
    String? handle,
  }) async {
    final params = <String, dynamic>{'slug': slug};
    if (name != null && name.isNotEmpty) params['name'] = name;
    if (handle != null && handle.isNotEmpty) params['handle'] = handle;
    final result = await _call('create_org', params);
    final map = result as Map<String, dynamic>? ?? {};
    return OnboardResult(
      handle: map['handle'] as String? ?? '',
      orgId: map['org_id'] as String? ?? '',
    );
  }

  /// Join via invite after Auth0 (`POST /v1/onboarding/join`).
  Future<OnboardResult> joinOrg({
    required String inviteCode,
    String? handle,
  }) async {
    final params = <String, dynamic>{'invite_code': inviteCode};
    if (handle != null && handle.isNotEmpty) params['handle'] = handle;
    final result = await _call('join_org', params);
    final map = result as Map<String, dynamic>? ?? {};
    return OnboardResult(
      handle: map['handle'] as String? ?? handle ?? '',
      orgId: map['org_id'] as String? ?? '',
    );
  }

  /// Write MCP host configs via JSON-RPC `connect_host`.
  ///
  /// [host] is `cursor`, `claude`, `chatgpt`, or `all`.
  Future<ConnectHostResult> connectHost(String host) async {
    final result = await _call('connect_host', {'host': host});
    final map = result as Map<String, dynamic>? ?? {};
    final hostsRaw = map['hosts'] as List<dynamic>? ?? const [];
    return ConnectHostResult(
      command: map['command'] as String? ?? '',
      args: (map['args'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      hosts: hostsRaw.map((e) {
        final m = e as Map<String, dynamic>;
        return HostWriteResult(
          host: m['host'] as String? ?? '',
          path: m['path'] as String? ?? '',
          ok: m['ok'] == true,
          command: m['command'] as String?,
          note: m['note'] as String?,
        );
      }).toList(),
    );
  }

  /// Org members + synthetic `@all@org` via JSON-RPC `list_contacts`.
  Future<List<ContactView>> listContacts() async {
    final result = await _callWithTimeout(
      'list_contacts',
      null,
      requestTimeout,
    );
    final map = result as Map<String, dynamic>? ?? {};
    final raw = map['contacts'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => ContactView.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Pilot / product feedback → hub `POST /v1/feedback`.
  Future<void> submitFeedback({
    required String message,
    String? category,
    String? appVersion,
  }) async {
    final params = <String, dynamic>{'message': message};
    if (category != null && category.isNotEmpty) {
      params['category'] = category;
    }
    if (appVersion != null && appVersion.isNotEmpty) {
      params['app_version'] = appVersion;
    }
    await _call('submit_feedback', params);
  }

  /// List threads via JSON-RPC `list_threads`.
  Future<List<ThreadSummary>> listThreads({String? filter}) async {
    final result = await _callWithTimeout(
      'list_threads',
      filter == null ? null : {'filter': filter},
      requestTimeout,
    );
    final map = result as Map<String, dynamic>? ?? {};
    final raw = map['threads'] as List<dynamic>? ?? const [];
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return ThreadSummary(
        id: m['id'] as String? ?? '',
        kind: m['kind'] as String? ?? '',
        status: m['status'] as String? ?? '',
        from: m['from'] as String? ?? '',
        audience: m['audience'] as String? ?? '',
        yourStatus: m['your_status'] as String?,
        replyCount: (m['reply_count'] as num?)?.toInt() ?? 0,
        agentBadge: _agentBadgeFromThread(m),
        // Hub `updated_at` advances on latest message activity.
        updatedAt: m['updated_at'] as String? ?? m['created_at'] as String?,
        lastFrom: m['last_from'] as String?,
        lastSubject: m['last_subject'] as String?,
        lastPreview: m['last_preview'] as String?,
      );
    }).toList();
  }

  /// Open + decrypt thread via JSON-RPC `get_thread`.
  Future<ThreadDetailResult> getThread(String threadId) async {
    final result = await _call('get_thread', {'thread_id': threadId});
    final map = result as Map<String, dynamic>? ?? {};
    final thread = map['thread'] as Map<String, dynamic>? ?? {};
    final messagesRaw = map['messages'] as List<dynamic>? ?? const [];
    return ThreadDetailResult(
      id: thread['id'] as String? ?? threadId,
      kind: thread['kind'] as String? ?? '',
      status: thread['status'] as String? ?? '',
      from: thread['from'] as String? ?? '',
      audience: thread['audience'] as String? ?? '',
      yourStatus: thread['your_status'] as String?,
      messages: messagesRaw.map((e) {
        final m = e as Map<String, dynamic>;
        final bundle = m['bundle'] as Map<String, dynamic>?;
        final questionsRaw = bundle?['questions'] as List<dynamic>? ?? const [];
        final questions = questionsRaw
            .map((q) {
              final map = q as Map<String, dynamic>? ?? const {};
              return map['prompt'] as String? ?? '';
            })
            .where((p) => p.trim().isNotEmpty)
            .toList();
        final resourceReqs =
            bundle?['resource_requests'] as List<dynamic>? ?? const [];
        final resources = resourceReqs
            .map((r) {
              final map = r as Map<String, dynamic>? ?? const {};
              return map['description'] as String? ?? map['id'] as String? ?? '';
            })
            .where((d) => d.trim().isNotEmpty)
            .toList();
        final answersRaw = bundle?['answers'] as List<dynamic>? ?? const [];
        final answers = answersRaw
            .map((a) {
              final map = a as Map<String, dynamic>? ?? const {};
              return map['answer'] as String? ?? '';
            })
            .where((a) => a.trim().isNotEmpty)
            .toList();
        return ThreadMessageView(
          id: m['id'] as String? ?? '',
          fromHandle: m['from_handle'] as String? ?? '',
          createdAt: m['created_at'] as String? ?? '',
          parentMessageId: m['parent_message_id'] as String?,
          inReplyTo: bundle?['in_reply_to'] as String?,
          bundleSubject: bundle?['subject'] as String?,
          bundleNotes:
              bundle?['notes'] as String? ?? bundle?['context'] as String?,
          pingKind: bundle?['ping_kind'] as String?,
          questionPrompts: questions,
          resourceRequests: resources,
          answerTexts: answers,
          openError: m['open_error'] as String?,
          upvotes: MessageUpvoteSummaryView.fromJson(
            m['upvotes'] as Map<String, dynamic>?,
          ),
        );
      }).toList(),
    );
  }

  /// Reply with a notes-only bundle via JSON-RPC `reply_to_thread`.
  Future<void> replyToThread({
    required String threadId,
    required String notes,
    String? toAgent,
    String? inReplyTo,
  }) async {
    final trimmed = notes.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Reply cannot be empty');
    }
    await _call('reply_to_thread', {
      'thread_id': threadId,
      'bundle': {
        'notes': trimmed,
        if (inReplyTo != null) 'in_reply_to': inReplyTo,
      },
      if (toAgent != null) 'to_agent': toAgent,
    });
  }

  /// Toggle agent upvote on a message (coordination weight).
  Future<MessageUpvoteSummaryView> toggleMessageUpvote({
    required String threadId,
    required String messageId,
    String? agentSlug,
  }) async {
    final result = await _call('toggle_message_upvote', {
      'thread_id': threadId,
      'message_id': messageId,
      if (agentSlug != null) 'agent_slug': agentSlug,
    });
    final map = result as Map<String, dynamic>? ?? {};
    return MessageUpvoteSummaryView.fromJson(
      map['upvotes'] as Map<String, dynamic>?,
    );
  }

  Future<AgentListResult> listAgents({String? handle}) async {
    final result = await _call(
      'list_agents',
      handle == null ? null : {'handle': handle},
    );
    final map = result as Map<String, dynamic>? ?? {};
    final raw = map['agents'] as List<dynamic>? ?? const [];
    return AgentListResult(
      agents: raw
          .map((e) => AgentInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      defaultAgentId: map['default_agent_id'] as String?,
    );
  }

  Future<void> setDefaultAgent(String agentId) async {
    await _call('set_default_agent', {'agent_id': agentId});
  }

  Future<AgentInfo> renameAgent({
    required String agentId,
    required String slug,
  }) async {
    final result = await _call('rename_agent', {
      'agent_id': agentId,
      'slug': slug,
    });
    return AgentInfo.fromJson(result as Map<String, dynamic>? ?? {});
  }

  Future<RouterConfig> getRouter() async {
    final result = await _call('get_router');
    return RouterConfig.fromJson(result as Map<String, dynamic>? ?? {});
  }

  Future<RouterConfig> setRouter({
    String? defaultAgentId,
    List<RoutingRule>? rules,
  }) async {
    final result = await _call('set_router', {
      if (defaultAgentId != null) 'default_agent_id': defaultAgentId,
      if (rules != null)
        'rules': rules
            .map((r) => {'match_slug': r.matchSlug, 'agent_id': r.agentId})
            .toList(),
    });
    return RouterConfig.fromJson(result as Map<String, dynamic>? ?? {});
  }

  /// Send notes to [recipient] (optional agent suffix) via `forward_draft`.
  Future<String> forwardDraft({
    required String recipient,
    required String notes,
  }) async {
    final result = await _call('forward_draft', {
      'recipient': recipient,
      'notes': notes,
    });
    final map = result as Map<String, dynamic>? ?? {};
    return map['thread_id'] as String? ?? '';
  }

  /// Mark a thread closed via JSON-RPC `close_thread`.
  Future<void> closeThread(String threadId) async {
    await _call('close_thread', {'thread_id': threadId});
  }

  /// Remove a thread from the inbox via JSON-RPC `delete_thread`.
  Future<void> deleteThread(String threadId) async {
    await _call('delete_thread', {'thread_id': threadId});
  }

  Future<SafetyNumberResult> getSafetyNumber() async {
    final result = await _call('get_safety_number');
    return SafetyNumberResult.fromJson(result as Map<String, dynamic>? ?? {});
  }

  Future<SafetyNumberResult> contactSafetyNumber(String handle) async {
    final result = await _call('contact_safety_number', {'handle': handle});
    return SafetyNumberResult.fromJson(result as Map<String, dynamic>? ?? {});
  }

  Future<SafetyNumberResult> verifyContact({
    required String handle,
    required String fingerprint,
  }) async {
    final result = await _call('verify_contact', {
      'handle': handle,
      'fingerprint': fingerprint,
    });
    return SafetyNumberResult.fromJson(result as Map<String, dynamic>? ?? {});
  }

  /// Persist absolute mutande-core path for Connect AI MCP configs.
  Future<void> setCorePath(String path) async {
    await _call('set_core_path', {'path': path});
  }

  /// Ping daemon liveness via JSON-RPC `health`.
  Future<DaemonHealthResult> pingHealth() async {
    try {
      final result = await _call('health');
      final map = result as Map<String, dynamic>? ?? {};
      final ok = map['ok'] == true;
      return DaemonHealthResult(
        connected: ok,
        service: map['service'] as String?,
        version: map['version'] as String?,
        transport: 'http',
        endpoint: httpBaseUrl,
      );
    } on DaemonException catch (e) {
      return DaemonHealthResult(
        connected: false,
        error: e.message,
        transport: 'http',
        endpoint: httpBaseUrl,
      );
    } catch (e) {
      return DaemonHealthResult(
        connected: false,
        error: e.toString(),
        transport: 'http',
        endpoint: httpBaseUrl,
      );
    }
  }

  /// Generic JSON-RPC 2.0 call over HTTP POST to `{base}/rpc`.
  Future<dynamic> _call(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    return _callWithTimeout(method, params, null);
  }

  Future<dynamic> _callWithTimeout(
    String method,
    Map<String, dynamic>? params,
    Duration? timeout,
  ) async {
    final id = ++_jsonRpcId;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
    };
    if (params != null) {
      payload['params'] = params;
    }
    final body = jsonEncode(payload);

    final token = _resolveHttpToken();
    if (token == null || token.isEmpty) {
      throw DaemonException(
        'Missing HTTP token at $httpTokenPath '
        '(start mutande-core serve to create it)',
      );
    }

    final uri = Uri.parse('$httpBaseUrl/rpc');
    final response = await _http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(timeout ?? requestTimeout);

    if (response.statusCode == 401) {
      _cachedHttpToken = null;
      throw DaemonException(
        'HTTP 401 unauthorized — check $httpTokenPath matches the running daemon',
      );
    }

    if (response.statusCode != 200) {
      throw DaemonException(
        'HTTP ${response.statusCode} from daemon at $httpBaseUrl',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw DaemonException('Invalid JSON-RPC response');
    }

    if (decoded.containsKey('error')) {
      final err = decoded['error'];
      final message = err is Map ? err['message']?.toString() : err.toString();
      throw DaemonException(message ?? 'Daemon error');
    }

    return decoded['result'];
  }

  String? _resolveHttpToken() {
    if (_httpTokenOverride != null) {
      return _httpTokenOverride;
    }
    if (_cachedHttpToken != null) {
      return _cachedHttpToken;
    }
    final path = _expandHome(httpTokenPath);
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final token = file.readAsStringSync().trim();
    if (token.isEmpty) {
      return null;
    }
    _cachedHttpToken = token;
    return token;
  }

  static String _expandHome(String path) => expandUserPath(path);

  void dispose() => _http.close();
}

class DaemonHealthResult {
  const DaemonHealthResult({
    required this.connected,
    this.service,
    this.version,
    this.error,
    this.transport,
    this.endpoint,
  });

  final bool connected;
  final String? service;
  final String? version;
  final String? error;
  final String? transport;
  final String? endpoint;
}

class DaemonStatusResult {
  const DaemonStatusResult({
    required this.configured,
    this.signedIn = false,
    this.needsOnboarding = false,
    this.hubUrl,
    this.handle,
    this.orgId,
    this.email,
    this.connectedAgent,
    this.defaultAgent,
  });

  factory DaemonStatusResult.fromJson(Map<String, dynamic> map) {
    return DaemonStatusResult(
      configured: map['configured'] == true,
      signedIn: map['signed_in'] == true,
      needsOnboarding: map['needs_onboarding'] == true,
      hubUrl: map['hub_url'] as String?,
      handle: map['handle'] as String?,
      orgId: map['org_id'] as String?,
      email: map['email'] as String?,
      connectedAgent: map['connected_agent'] as String?,
      defaultAgent: map['default_agent'] as String?,
    );
  }

  final bool configured;
  final bool signedIn;
  final bool needsOnboarding;
  final String? hubUrl;
  final String? handle;
  final String? orgId;
  final String? email;
  final String? connectedAgent;
  final String? defaultAgent;
}

class OnboardResult {
  const OnboardResult({required this.handle, required this.orgId});

  final String handle;
  final String orgId;
}

class ConnectHostResult {
  const ConnectHostResult({
    required this.command,
    required this.args,
    required this.hosts,
  });

  final String command;
  final List<String> args;
  final List<HostWriteResult> hosts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectHostResult &&
          command == other.command &&
          _listEq(args, other.args) &&
          _listEq(hosts, other.hosts);

  @override
  int get hashCode => Object.hash(command, Object.hashAll(args), Object.hashAll(hosts));
}

class HostWriteResult {
  const HostWriteResult({
    required this.host,
    required this.path,
    required this.ok,
    this.command,
    this.note,
  });

  final String host;
  final String path;
  final bool ok;
  final String? command;
  final String? note;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostWriteResult &&
          host == other.host &&
          path == other.path &&
          ok == other.ok &&
          command == other.command &&
          note == other.note;

  @override
  int get hashCode => Object.hash(host, path, ok, command, note);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class DaemonException implements Exception {
  DaemonException(this.message);
  final String message;

  @override
  String toString() => 'DaemonException: $message';
}

class ThreadSummary {
  const ThreadSummary({
    required this.id,
    required this.kind,
    required this.status,
    required this.from,
    required this.audience,
    this.yourStatus,
    this.replyCount = 0,
    this.agentBadge,
    this.updatedAt,
    this.lastFrom,
    this.lastSubject,
    this.lastPreview,
  });

  final String id;
  final String kind;
  final String status;
  final String from;
  final String audience;
  final String? yourStatus;
  final int replyCount;
  final String? agentBadge;
  /// ISO timestamp of latest thread activity (last message).
  final String? updatedAt;
  /// Author of the latest opened message (daemon-local).
  final String? lastFrom;
  /// Subject for the list title (latest, else OP — daemon-local).
  final String? lastSubject;
  /// Body preview of the latest message (daemon-local).
  final String? lastPreview;

  ThreadSummary copyWith({
    String? status,
    String? yourStatus,
    int? replyCount,
    String? agentBadge,
    String? updatedAt,
    String? lastFrom,
    String? lastSubject,
    String? lastPreview,
  }) {
    return ThreadSummary(
      id: id,
      kind: kind,
      status: status ?? this.status,
      from: from,
      audience: audience,
      yourStatus: yourStatus ?? this.yourStatus,
      replyCount: replyCount ?? this.replyCount,
      agentBadge: agentBadge ?? this.agentBadge,
      updatedAt: updatedAt ?? this.updatedAt,
      lastFrom: lastFrom ?? this.lastFrom,
      lastSubject: lastSubject ?? this.lastSubject,
      lastPreview: lastPreview ?? this.lastPreview,
    );
  }

  /// List-row fingerprint for merge / skip-rebuild checks.
  bool sameListRow(ThreadSummary other) {
    return id == other.id &&
        kind == other.kind &&
        status == other.status &&
        from == other.from &&
        audience == other.audience &&
        yourStatus == other.yourStatus &&
        replyCount == other.replyCount &&
        agentBadge == other.agentBadge &&
        updatedAt == other.updatedAt &&
        lastFrom == other.lastFrom &&
        lastSubject == other.lastSubject &&
        lastPreview == other.lastPreview;
  }
}

class AgentInfo {
  const AgentInfo({required this.id, required this.slug});

  factory AgentInfo.fromJson(Map<String, dynamic> map) {
    return AgentInfo(
      id: map['id'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
    );
  }

  final String id;
  final String slug;
}

class AgentListResult {
  const AgentListResult({required this.agents, this.defaultAgentId});

  final List<AgentInfo> agents;
  final String? defaultAgentId;
}

class RoutingRule {
  const RoutingRule({required this.matchSlug, required this.agentId});

  factory RoutingRule.fromJson(Map<String, dynamic> map) {
    return RoutingRule(
      matchSlug: map['match_slug'] as String? ?? '',
      agentId: map['agent_id'] as String? ?? '',
    );
  }

  final String matchSlug;
  final String agentId;
}

class RouterConfig {
  const RouterConfig({this.defaultAgentId, this.rules = const []});

  factory RouterConfig.fromJson(Map<String, dynamic> map) {
    final raw = map['rules'] as List<dynamic>? ?? const [];
    return RouterConfig(
      defaultAgentId: map['default_agent_id'] as String?,
      rules: raw
          .map((e) => RoutingRule.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String? defaultAgentId;
  final List<RoutingRule> rules;
}

String? _agentBadgeFromThread(Map<String, dynamic> m) {
  for (final field in ['audience', 'from']) {
    final value = m[field] as String?;
    if (value == null) continue;
    final slash = value.indexOf('/');
    if (slash >= 0 && slash < value.length - 1) {
      return value.substring(slash + 1);
    }
  }
  return null;
}

class ContactView {
  const ContactView({required this.handle, this.pubkey, this.devices = const []});

  factory ContactView.fromJson(Map<String, dynamic> map) {
    final devicesRaw = map['devices'] as List<dynamic>? ?? const [];
    return ContactView(
      handle: map['handle'] as String? ?? '',
      pubkey: map['pubkey'] as String?,
      devices: devicesRaw
          .map((e) => ContactDeviceView.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String handle;
  final String? pubkey;
  final List<ContactDeviceView> devices;

  bool get isBroadcast => handle.startsWith('@all@');
}

class ContactDeviceView {
  const ContactDeviceView({required this.pubkey, this.platform});

  factory ContactDeviceView.fromJson(Map<String, dynamic> map) {
    return ContactDeviceView(
      pubkey: map['pubkey'] as String? ?? '',
      platform: map['platform'] as String?,
    );
  }

  final String pubkey;
  final String? platform;
}

class ThreadDetailResult {
  const ThreadDetailResult({
    required this.id,
    required this.kind,
    required this.status,
    required this.from,
    this.audience = '',
    this.yourStatus,
    required this.messages,
  });

  final String id;
  final String kind;
  final String status;
  final String from;
  final String audience;
  final String? yourStatus;
  final List<ThreadMessageView> messages;
}

class ThreadMessageView {
  const ThreadMessageView({
    required this.id,
    required this.fromHandle,
    required this.createdAt,
    this.parentMessageId,
    this.inReplyTo,
    this.bundleSubject,
    this.bundleNotes,
    this.pingKind,
    this.questionPrompts = const [],
    this.resourceRequests = const [],
    this.answerTexts = const [],
    this.openError,
    this.upvotes,
  });

  final String id;
  final String fromHandle;
  final String createdAt;
  final String? parentMessageId;
  final String? inReplyTo;
  final String? bundleSubject;
  final String? bundleNotes;
  /// Bundle `ping_kind`: `health` | `thread`, when present.
  final String? pingKind;
  final List<String> questionPrompts;
  final List<String> resourceRequests;
  final List<String> answerTexts;
  final String? openError;
  final MessageUpvoteSummaryView? upvotes;

  ThreadMessageView copyWithUpvotes(MessageUpvoteSummaryView? upvotes) {
    return ThreadMessageView(
      id: id,
      fromHandle: fromHandle,
      createdAt: createdAt,
      parentMessageId: parentMessageId,
      inReplyTo: inReplyTo,
      bundleSubject: bundleSubject,
      bundleNotes: bundleNotes,
      pingKind: pingKind,
      questionPrompts: questionPrompts,
      resourceRequests: resourceRequests,
      answerTexts: answerTexts,
      openError: openError,
      upvotes: upvotes,
    );
  }

  /// Resolved parent for tree layout (hub metadata preferred).
  String? get replyParentId => parentMessageId ?? inReplyTo;

  /// True when decrypt succeeded but the bundle has no displayable content.
  bool get isEmptyBody {
    if (openError != null && openError!.trim().isNotEmpty) return false;
    return _contentParts.isEmpty;
  }

  List<String> get _contentParts => [
        if (bundleSubject != null && bundleSubject!.trim().isNotEmpty)
          bundleSubject!.trim(),
        if (bundleNotes != null && bundleNotes!.trim().isNotEmpty)
          bundleNotes!.trim(),
        ...questionPrompts.map((q) => q.trim()).where((q) => q.isNotEmpty),
        ...answerTexts.map((a) => a.trim()).where((a) => a.isNotEmpty),
        ...resourceRequests
            .map((r) => r.trim())
            .where((r) => r.isNotEmpty)
            .map((r) => 'Resource: $r'),
      ];

  /// Prefer notes/subject, then questions/answers — never hide question-only handoffs.
  String get displayBody {
    if (openError != null && openError!.trim().isNotEmpty) {
      return openError!;
    }
    final parts = _contentParts;
    if (parts.isEmpty) return 'No message body';
    return parts.join('\n\n');
  }
}

class MessageUpvoteView {
  const MessageUpvoteView({
    required this.agentId,
    required this.fromHandle,
    required this.createdAt,
  });

  factory MessageUpvoteView.fromJson(Map<String, dynamic> map) {
    return MessageUpvoteView(
      agentId: map['agent_id'] as String? ?? '',
      fromHandle: map['from_handle'] as String? ?? '',
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  final String agentId;
  final String fromHandle;
  final String createdAt;

  /// Short label for chips — prefer agent suffix after `/`.
  String get chipLabel {
    final slash = fromHandle.indexOf('/');
    if (slash >= 0 && slash < fromHandle.length - 1) {
      return fromHandle.substring(slash + 1);
    }
    return fromHandle;
  }
}

class MessageUpvoteSummaryView {
  const MessageUpvoteSummaryView({
    required this.count,
    this.upvotes = const [],
    this.yourUpvotes = const [],
  });

  factory MessageUpvoteSummaryView.fromJson(Map<String, dynamic>? map) {
    if (map == null) return const MessageUpvoteSummaryView(count: 0);
    final raw = map['upvotes'] as List<dynamic>? ?? const [];
    final yours = map['your_upvotes'] as List<dynamic>? ?? const [];
    return MessageUpvoteSummaryView(
      count: map['count'] as int? ?? raw.length,
      upvotes: raw
          .map((e) => MessageUpvoteView.fromJson(e as Map<String, dynamic>))
          .toList(),
      yourUpvotes: yours.map((e) => e as String).toList(),
    );
  }

  final int count;
  final List<MessageUpvoteView> upvotes;
  final List<String> yourUpvotes;

  bool get youUpvoted => yourUpvotes.isNotEmpty;
}

class SafetyNumberResult {
  const SafetyNumberResult({
    required this.handle,
    required this.fingerprint,
    required this.uri,
    this.verified,
  });

  factory SafetyNumberResult.fromJson(Map<String, dynamic> map) {
    return SafetyNumberResult(
      handle: map['handle'] as String? ?? '',
      fingerprint: map['fingerprint'] as String? ?? '',
      uri: map['uri'] as String? ?? '',
      verified: map['verified'] as bool?,
    );
  }

  final String handle;
  final String fingerprint;
  final String uri;
  final bool? verified;
}

/// Light client-side checks before calling register RPC.
String? validateHandle(String handle) {
  final trimmed = handle.trim();
  if (trimmed.isEmpty) return 'Handle is required.';
  final at = trimmed.indexOf('@');
  if (at <= 0 || at == trimmed.length - 1 || trimmed.contains(' ')) {
    return 'Handle must look like alice@acme.';
  }
  return null;
}

String? validateHubUrl(String hubUrl) {
  final trimmed = hubUrl.trim();
  if (trimmed.isEmpty) return 'Hub URL is required.';
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return 'Hub URL must be an http(s) URL.';
  }
  return null;
}

/// User-facing copy for daemon/hub failures — never raw `TimeoutException…`.
String friendlyDaemonError(Object error, {String what = 'That'}) {
  var msg = error.toString();
  if (msg.startsWith('DaemonException: ')) {
    msg = msg.substring('DaemonException: '.length);
  }
  if (msg.startsWith('Exception: ')) {
    msg = msg.substring('Exception: '.length);
  }
  if (msg.startsWith('TimeoutException')) {
    msg = 'timed out';
  }
  final lower = msg.toLowerCase();
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return '$what took too long. The courier may still be starting — try again.';
  }
  if (lower.contains('missing http token') ||
      lower.contains('connection refused') ||
      lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('matches the running daemon')) {
    return "Can't reach the local mutande daemon. Open Settings and tap Check daemon.";
  }
  if (lower.contains('401') ||
      lower.contains('unauthorized') ||
      lower.contains('hub error 401')) {
    return 'Sign-in expired or was rejected. Open Settings and sign in again.';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return "Couldn't load $what. Check you're signed in, then retry.";
  }
  if (lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503')) {
    return "Couldn't reach the hub. Try again in a moment.";
  }
  return msg;
}
