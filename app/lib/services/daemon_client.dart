import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/agent_transport.dart';
import '../platform/user_home.dart';
import 'daemon_errors.dart';

/// Local IPC client for `mutande-core serve`.
///
/// App transport (current): JSON-RPC 2.0 over HTTP POST to
/// `{httpBaseUrl}/rpc` (dev bridge). Inbox push uses WebSocket
/// `ws://127.0.0.1:3847/ws` ([DaemonEventClient]). Daemon-native transport is a
/// Unix domain socket at `~/.mutande/daemon.sock` (`mutande-core serve --socket`);
/// this client does not speak the Unix socket yet — [socketPath] is informational only.
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
/// | `auth_logout` | Clear Auth0 tokens; keep hub URL for re-login |
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
/// | `get_safety_number` | Own fingerprint + URI + hex `pubkey` |
/// | `register_device` | Force-publish this device pubkey to the hub |
/// | `get_transport_defaults` | Hub preferred transport per slug |
/// | `set_transport_default` | Hub Settings write for preferred transport |
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
  }) : _http = httpClient ?? http.Client(),
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

  /// Clear Auth0 tokens locally (device Keychain identity kept).
  Future<DaemonStatusResult> authLogout() async {
    final result = await _call('auth_logout', null);
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
  /// Longer timeout: copies `mutande-core` into `~/.mutande/bin` + preflight.
  Future<ConnectHostResult> connectHost(String host) async {
    final result = await _callWithTimeout('connect_host', {
      'host': host,
    }, const Duration(seconds: 60));
    final map = result as Map<String, dynamic>? ?? {};
    final hostsRaw = map['hosts'] as List<dynamic>? ?? const [];
    return ConnectHostResult(
      command: map['command'] as String? ?? '',
      args:
          (map['args'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
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

  /// Probe installed desktop apps + MCP config paths (`detect_ai_hosts` RPC).
  Future<List<AiHostDetection>> detectAiHosts() async {
    try {
      final result = await _callWithTimeout(
        'detect_ai_hosts',
        null,
        requestTimeout,
      );
      final map = result as Map<String, dynamic>? ?? {};
      final raw = map['hosts'] as List<dynamic>? ?? const [];
      return raw
          .map((e) => AiHostDetection.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _detectAiHostsLocal();
    }
  }

  List<AiHostDetection> _detectAiHostsLocal() {
    if (!Platform.isMacOS) {
      return const [
        AiHostDetection(host: 'cursor', installed: false, configPresent: false),
        AiHostDetection(host: 'claude', installed: false, configPresent: false),
        AiHostDetection(
          host: 'chatgpt',
          installed: false,
          configPresent: false,
        ),
      ];
    }
    final home = userHomeDir() ?? '';
    bool appInstalled(String name) {
      return Directory('/Applications/$name.app').existsSync() ||
          Directory('$home/Applications/$name.app').existsSync();
    }

    bool configPresent(String host) {
      switch (host) {
        case 'cursor':
          return File('$home/.cursor/mcp.json').existsSync();
        case 'claude':
          return File(
            '$home/Library/Application Support/Claude/claude_desktop_config.json',
          ).existsSync();
        case 'chatgpt':
          return File(
            '$home/Library/Application Support/ChatGPT/mcp.json',
          ).existsSync();
        default:
          return false;
      }
    }

    return ['cursor', 'claude', 'chatgpt'].map((host) {
      final appName = switch (host) {
        'cursor' => 'Cursor',
        'claude' => 'Claude',
        _ => 'ChatGPT',
      };
      return AiHostDetection(
        host: host,
        installed: appInstalled(appName),
        configPresent: configPresent(host),
      );
    }).toList();
  }

  /// Install or stage the mutande agent skill for a host (`cursor`|`claude`|`chatgpt`).
  Future<InstallSkillResult> installSkill(String host) async {
    final result = await _callWithTimeout('install_skill', {
      'host': host,
    }, const Duration(seconds: 45));
    final map = result as Map<String, dynamic>? ?? {};
    return InstallSkillResult.fromJson(map);
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

  /// Cross-org external contacts (approved links).
  Future<List<ContactView>> listExternalContacts() async {
    final result = await _callWithTimeout(
      'list_external_contacts',
      null,
      requestTimeout,
    );
    final map = result as Map<String, dynamic>? ?? {};
    final raw = map['contacts'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => ContactView.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PairingPinView> issuePairingPin() async {
    final result = await _call('issue_pairing_pin', null);
    return PairingPinView.fromJson(result as Map<String, dynamic>? ?? {});
  }

  Future<PairingPinView?> getPairingPin() async {
    final result = await _call('get_pairing_pin', null);
    final map = result as Map<String, dynamic>? ?? {};
    final pin = map['pin'];
    if (pin is Map<String, dynamic>) {
      return PairingPinView.fromJson(pin);
    }
    return null;
  }

  Future<PairingPinView> rotatePairingPin() async {
    final result = await _call('rotate_pairing_pin', null);
    return PairingPinView.fromJson(result as Map<String, dynamic>? ?? {});
  }

  Future<PairRequestView> submitPairRequest({
    required String handle,
    required String pin,
    String? intro,
  }) async {
    final params = <String, dynamic>{'handle': handle, 'pin': pin};
    if (intro != null && intro.trim().isNotEmpty) {
      params['intro'] = intro.trim();
    }
    final result = await _call('submit_pair_request', params);
    final map = result as Map<String, dynamic>? ?? {};
    return PairRequestView.fromJson(
      map['request'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<PendingPairRequestsView> listPendingPairRequests() async {
    final result = await _call('list_pending_pair_requests', null);
    return PendingPairRequestsView.fromJson(
      result as Map<String, dynamic>? ?? {},
    );
  }

  Future<void> approvePairRequest(String requestId) async {
    await _call('approve_pair_request', {'request_id': requestId});
  }

  Future<void> denyPairRequest(String requestId) async {
    await _call('deny_pair_request', {'request_id': requestId});
  }

  Future<void> unpairExternalContact(String linkId) async {
    await _call('unpair_external_contact', {'link_id': linkId});
  }

  /// L5: propose adding a web agent to an E2E thread (unanimous sidecar approve).
  Future<ThreadDowngradeProposalView> proposeThreadDowngrade({
    required String threadId,
    required String agentSlug,
    String? fromAgent,
  }) async {
    final params = <String, dynamic>{
      'thread_id': threadId,
      'agent_slug': agentSlug,
    };
    if (fromAgent != null && fromAgent.trim().isNotEmpty) {
      params['from_agent'] = fromAgent.trim();
    }
    final result = await _call('propose_thread_downgrade', params);
    final map = result as Map<String, dynamic>? ?? {};
    return ThreadDowngradeProposalView.fromJson(
      map['proposal'] as Map<String, dynamic>? ?? {},
      prompt: map['prompt'] as String?,
    );
  }

  Future<List<ThreadDowngradeProposalView>>
  listPendingThreadDowngrades() async {
    final result = await _call('list_pending_thread_downgrades', null);
    final map = result as Map<String, dynamic>? ?? {};
    final raw = map['proposals'] as List<dynamic>? ?? const [];
    return raw
        .map(
          (e) => ThreadDowngradeProposalView.fromJson(
            e as Map<String, dynamic>? ?? {},
          ),
        )
        .toList();
  }

  Future<void> approveThreadDowngrade({
    required String threadId,
    required String proposalId,
  }) async {
    await _call('approve_thread_downgrade', {
      'thread_id': threadId,
      'proposal_id': proposalId,
    });
  }

  Future<void> denyThreadDowngrade({
    required String threadId,
    required String proposalId,
  }) async {
    await _call('deny_thread_downgrade', {
      'thread_id': threadId,
      'proposal_id': proposalId,
    });
  }

  Future<void> approveTask({
    required String threadId,
    required String messageId,
  }) async {
    await _call('approve_task', {
      'thread_id': threadId,
      'message_id': messageId,
    });
  }

  Future<void> denyTask({
    required String threadId,
    required String messageId,
  }) async {
    await _call('deny_task', {'thread_id': threadId, 'message_id': messageId});
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
        awaiting: AwaitingEntry.listFrom(m['awaiting']),
        replyCount: (m['reply_count'] as num?)?.toInt() ?? 0,
        agentBadge: _agentBadgeFromThread(m),
        // Hub `updated_at` advances on latest message activity.
        updatedAt: m['updated_at'] as String? ?? m['created_at'] as String?,
        lastFrom: m['last_from'] as String?,
        lastSubject: m['last_subject'] as String?,
        lastPreview: m['last_preview'] as String?,
        collabId: m['collab_id'] as String?,
        collabName: m['collab_name'] as String?,
        laneId: m['lane_id'] as String?,
        assignedTo: m['assigned_to'] as String?,
      );
    }).toList();
  }

  /// Open + decrypt thread via JSON-RPC `get_thread`.
  Future<ThreadDetailResult> getThread(String threadId) async {
    final result = await _call('get_thread', {'thread_id': threadId});
    final map = result as Map<String, dynamic>? ?? {};
    final thread = map['thread'] as Map<String, dynamic>? ?? {};
    final messagesRaw = map['messages'] as List<dynamic>? ?? const [];
    final pendingRaw = map['pending_downgrade'] as Map<String, dynamic>?;
    final taskApprovalsRaw =
        map['pending_task_approvals'] as List<dynamic>? ?? const [];
    return ThreadDetailResult(
      id: thread['id'] as String? ?? threadId,
      kind: thread['kind'] as String? ?? '',
      status: thread['status'] as String? ?? '',
      from: thread['from'] as String? ?? '',
      audience: thread['audience'] as String? ?? '',
      yourStatus: thread['your_status'] as String?,
      awaiting: AwaitingEntry.listFrom(thread['awaiting']),
      enterpriseListingId: thread['enterprise_listing_id'] as String?,
      pendingDowngrade: pendingRaw == null
          ? null
          : ThreadDowngradeProposalView.fromJson(pendingRaw),
      pendingTaskApprovals: taskApprovalsRaw
          .whereType<Map>()
          .map(
            (e) =>
                PendingTaskApprovalView.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
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
        final resourceRequests = resourceReqs
            .map((r) {
              final map = r as Map<String, dynamic>? ?? const {};
              return map['description'] as String? ??
                  map['id'] as String? ??
                  '';
            })
            .where((d) => d.trim().isNotEmpty)
            .toList();
        final resourcesRaw = bundle?['resources'] as List<dynamic>? ?? const [];
        final resources = resourcesRaw
            .map(
              (r) => BundleResourceView.fromJson(
                r as Map<String, dynamic>? ?? const {},
              ),
            )
            .where((r) => r.name.trim().isNotEmpty)
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
          resourceRequests: resourceRequests,
          resources: resources,
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

  /// Public enterprise listing + warn banner (§7.2).
  ///
  /// Returns null when the address is not a published listing (404 / error).
  Future<RegistryListingWarn?> getRegistryListing(String idOrAddress) async {
    final trimmed = idOrAddress.trim();
    if (trimmed.isEmpty) return null;
    try {
      final result = await _call('get_registry_listing', {
        'id_or_address': trimmed,
      });
      return RegistryListingWarn.fromJson(
        result as Map<String, dynamic>? ?? const {},
      );
    } catch (_) {
      return null;
    }
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

  /// Hub preferred transport per display slug (`GET /v1/agents/transport-defaults`).
  ///
  /// Wire: `{ defaults: { slug: "sidecar"|"mcp" } }`.
  Future<Map<String, dynamic>> getTransportDefaults() async {
    final result = await _call('get_transport_defaults');
    return result as Map<String, dynamic>? ?? const {};
  }

  /// Hub Settings write (`PUT /v1/agents/transport-defaults`).
  Future<Map<String, dynamic>> setTransportDefault({
    required String slug,
    required AgentTransport transport,
  }) async {
    final result = await _call('set_transport_default', {
      'slug': slug,
      'transport': transport.wireValue,
    });
    return result as Map<String, dynamic>? ?? const {};
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

  Future<CollabListResult> listCollabs() async {
    final result = await _call('list_collabs');
    final map = result as Map<String, dynamic>? ?? {};
    final raw = map['collabs'] as List<dynamic>? ?? const [];
    final collabs = raw
        .map((e) => CollabSummary.fromJson(e as Map<String, dynamic>? ?? {}))
        .toList();
    return CollabListResult(
      collabs: collabs,
      portfolio: CollabPortfolio.fromJson(
        map['portfolio'] as Map<String, dynamic>?,
        collabs,
      ),
    );
  }

  Future<CollabDetail> getCollab(String collabId) async {
    final result = await _call('get_collab', {'collab_id': collabId});
    final map = result as Map<String, dynamic>? ?? {};
    final collab = map['collab'] as Map<String, dynamic>? ?? map;
    return CollabDetail.fromJson(collab);
  }

  Future<CollabDetail> createCollab({
    required String name,
    List<String> steererHandles = const [],
    List<String> rosterAddresses = const [],
    String? instructions,
    List<Map<String, dynamic>> artifacts = const [],
  }) async {
    final result = await _call('create_collab', {
      'name': name,
      if (steererHandles.isNotEmpty) 'steerer_handles': steererHandles,
      if (rosterAddresses.isNotEmpty) 'roster_addresses': rosterAddresses,
      if (instructions != null) 'instructions': instructions,
      if (artifacts.isNotEmpty) 'artifacts': artifacts,
    });
    final map = result as Map<String, dynamic>? ?? {};
    final collab = map['collab'] as Map<String, dynamic>? ?? map;
    return CollabDetail.fromJson(collab);
  }

  Future<void> setLane({
    required String collabId,
    required String threadId,
    required String laneId,
    String? beforeThreadId,
    String? afterThreadId,
  }) async {
    await _call('set_lane', {
      'collab_id': collabId,
      'thread_id': threadId,
      'lane_id': laneId,
      if (beforeThreadId != null) 'before_thread_id': beforeThreadId,
      if (afterThreadId != null) 'after_thread_id': afterThreadId,
    });
  }

  Future<void> addLearning({
    required String collabId,
    required String notes,
  }) async {
    await _call('add_learning', {'collab_id': collabId, 'notes': notes});
  }

  Future<void> updateCollabInstructions({
    required String collabId,
    required String instructions,
  }) async {
    await _call('update_collab_instructions', {
      'collab_id': collabId,
      'instructions': instructions,
    });
  }

  Future<String> createCollabCard({
    required String collabId,
    required String title,
    String? notes,
    String? laneId,
    String? assignedTo,
  }) async {
    final result = await _call('create_collab_card', {
      'collab_id': collabId,
      'subject': title,
      if (notes != null) 'notes': notes,
      if (laneId != null) 'lane_id': laneId,
      if (assignedTo != null) 'assigned_to': assignedTo,
    });
    final map = result as Map<String, dynamic>? ?? {};
    return map['thread_id'] as String? ?? '';
  }

  Future<SafetyNumberResult> getSafetyNumber() async {
    final result = await _call('get_safety_number');
    return SafetyNumberResult.fromJson(result as Map<String, dynamic>? ?? {});
  }

  /// Force-publish this device pubkey to the hub. Returns hex pubkey on success.
  Future<String> registerDevice() async {
    final result = await _call('register_device');
    final map = result as Map<String, dynamic>? ?? {};
    return map['pubkey'] as String? ?? '';
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
  Future<dynamic> _call(String method, [Map<String, dynamic>? params]) async {
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

  /// Drop cached bearer token (e.g. after killing a stale courier).
  void invalidateHttpToken() {
    _cachedHttpToken = null;
  }

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
    this.auth0Sub,
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
      auth0Sub: map['auth0_sub'] as String?,
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
  final String? auth0Sub;
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
  int get hashCode =>
      Object.hash(command, Object.hashAll(args), Object.hashAll(hosts));
}

class AiHostDetection {
  const AiHostDetection({
    required this.host,
    required this.installed,
    required this.configPresent,
  });

  factory AiHostDetection.fromJson(Map<String, dynamic> map) {
    return AiHostDetection(
      host: map['host'] as String? ?? '',
      installed: map['installed'] == true,
      configPresent: map['config_present'] == true,
    );
  }

  final String host;
  final bool installed;
  final bool configPresent;
}

/// Merged view for onboarding host tiles.
class AiHostPresence {
  const AiHostPresence({
    required this.slug,
    required this.installed,
    required this.configPresent,
    required this.linked,
    required this.agentRegistered,
  });

  final String slug;
  final bool installed;
  final bool configPresent;
  final bool linked;
  final bool agentRegistered;

  String get primaryBadge {
    if (linked && agentRegistered) return 'Connected';
    if (installed) return 'Installed';
    return 'Not detected';
  }

  int get sortOrder {
    if (linked && agentRegistered) return 2;
    if (installed) return 0;
    return 3;
  }
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

/// Result of JSON-RPC `install_skill`.
class InstallSkillResult {
  const InstallSkillResult({
    required this.host,
    required this.ok,
    required this.mode,
    this.path,
    this.zipPath,
    this.hint,
  });

  factory InstallSkillResult.fromJson(Map<String, dynamic> map) {
    return InstallSkillResult(
      host: map['host'] as String? ?? '',
      ok: map['ok'] == true,
      mode: map['mode'] as String? ?? 'auto',
      path: map['path'] as String?,
      zipPath: map['zip_path'] as String?,
      hint: map['hint'] as String?,
    );
  }

  final String host;
  final bool ok;

  /// `auto` or `manual`.
  final String mode;
  final String? path;
  final String? zipPath;
  final String? hint;

  bool get isManual => mode == 'manual';
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
    this.awaiting = const [],
    this.replyCount = 0,
    this.agentBadge,
    this.updatedAt,
    this.lastFrom,
    this.lastSubject,
    this.lastPreview,
    this.collabId,
    this.collabName,
    this.laneId,
    this.assignedTo,
  });

  final String id;
  final String kind;
  final String status;
  final String from;
  final String audience;
  final String? yourStatus;
  final List<AwaitingEntry> awaiting;
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
  final String? collabId;
  final String? collabName;
  final String? laneId;
  final String? assignedTo;

  ThreadSummary copyWith({
    String? status,
    String? yourStatus,
    List<AwaitingEntry>? awaiting,
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
      awaiting: awaiting ?? this.awaiting,
      replyCount: replyCount ?? this.replyCount,
      agentBadge: agentBadge ?? this.agentBadge,
      updatedAt: updatedAt ?? this.updatedAt,
      lastFrom: lastFrom ?? this.lastFrom,
      lastSubject: lastSubject ?? this.lastSubject,
      lastPreview: lastPreview ?? this.lastPreview,
      collabId: collabId,
      collabName: collabName,
      laneId: laneId,
      assignedTo: assignedTo,
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
        _sameAwaiting(awaiting, other.awaiting) &&
        replyCount == other.replyCount &&
        agentBadge == other.agentBadge &&
        updatedAt == other.updatedAt &&
        lastFrom == other.lastFrom &&
        lastSubject == other.lastSubject &&
        lastPreview == other.lastPreview &&
        collabId == other.collabId &&
        collabName == other.collabName;
  }

  factory ThreadSummary.fromJson(Map<String, dynamic> map) {
    return ThreadSummary(
      id: map['id'] as String? ?? '',
      kind: map['kind'] as String? ?? '',
      status: map['status'] as String? ?? '',
      from: map['from'] as String? ?? '',
      audience: map['audience'] as String? ?? '',
      yourStatus: map['your_status'] as String?,
      awaiting: AwaitingEntry.listFrom(map['awaiting']),
      replyCount: (map['reply_count'] as num?)?.toInt() ?? 0,
      agentBadge: map['agent_badge'] as String?,
      updatedAt: map['updated_at'] as String?,
      lastFrom: map['last_from'] as String?,
      lastSubject: map['last_subject'] as String?,
      lastPreview: map['last_preview'] as String?,
      collabId: map['collab_id'] as String?,
      collabName: map['collab_name'] as String?,
      laneId: map['lane_id'] as String?,
      assignedTo: map['assigned_to'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'status': status,
    'from': from,
    'audience': audience,
    if (yourStatus != null) 'your_status': yourStatus,
    if (awaiting.isNotEmpty)
      'awaiting': awaiting.map((e) => e.toJson()).toList(),
    'reply_count': replyCount,
    if (agentBadge != null) 'agent_badge': agentBadge,
    if (updatedAt != null) 'updated_at': updatedAt,
    if (lastFrom != null) 'last_from': lastFrom,
    if (lastSubject != null) 'last_subject': lastSubject,
    if (lastPreview != null) 'last_preview': lastPreview,
    if (collabId != null) 'collab_id': collabId,
    if (collabName != null) 'collab_name': collabName,
    if (laneId != null) 'lane_id': laneId,
    if (assignedTo != null) 'assigned_to': assignedTo,
  };
}

class CollabListView {
  const CollabListView({
    required this.id,
    required this.name,
    required this.position,
  });

  factory CollabListView.fromJson(Map<String, dynamic> map) {
    return CollabListView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      position: (map['position'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String name;
  final double position;
}

class CollabRosterView {
  const CollabRosterView({
    required this.userId,
    required this.agentId,
    required this.address,
    this.transport,
  });

  factory CollabRosterView.fromJson(Map<String, dynamic> map) {
    return CollabRosterView(
      userId: map['user_id'] as String? ?? '',
      agentId: map['agent_id'] as String? ?? '',
      address: (map['address'] as String? ?? '').toLowerCase(),
      transport: map['transport'] as String?,
    );
  }

  final String userId;
  final String agentId;
  final String address;
  final String? transport;
}

class CollabLearningView {
  const CollabLearningView({
    required this.id,
    required this.createdAt,
    required this.fromHandle,
    this.notes,
    this.sealed = false,
  });

  factory CollabLearningView.fromJson(Map<String, dynamic> map) {
    return CollabLearningView(
      id: map['id'] as String? ?? '',
      createdAt: map['created_at'] as String? ?? '',
      fromHandle: (map['from_handle'] as String? ?? '').toLowerCase(),
      notes: map['notes'] as String?,
      sealed: map['sealed'] as bool? ?? false,
    );
  }

  final String id;
  final String createdAt;
  final String fromHandle;
  final String? notes;
  final bool sealed;
}

class CollabCardView {
  const CollabCardView({
    required this.id,
    this.laneId,
    this.lanePosition,
    this.assignedTo,
    this.status = 'open',
    this.from = '',
    this.audience = '',
    this.updatedAt,
    this.yourStatus,
    this.title,
  });

  factory CollabCardView.fromJson(Map<String, dynamic> map) {
    return CollabCardView(
      id: map['id'] as String? ?? '',
      laneId: map['lane_id'] as String?,
      lanePosition: (map['lane_position'] as num?)?.toDouble(),
      assignedTo: map['assigned_to'] as String?,
      status: map['status'] as String? ?? 'open',
      from: map['from'] as String? ?? '',
      audience: map['audience'] as String? ?? '',
      updatedAt: map['updated_at'] as String?,
      yourStatus: map['your_status'] as String?,
      title: map['last_subject'] as String? ?? map['title'] as String?,
    );
  }

  final String id;
  final String? laneId;
  final double? lanePosition;
  final String? assignedTo;
  final String status;
  final String from;
  final String audience;
  final String? updatedAt;
  final String? yourStatus;
  final String? title;

  bool get needsYou => yourStatus == 'pending';
}

class CollabSummary {
  const CollabSummary({
    required this.id,
    required this.name,
    required this.encryptionMode,
    this.cardCount = 0,
    this.openCount = 0,
    this.doingCount = 0,
    this.needsYouCount = 0,
    this.updatedAt,
    this.causeAddress,
  });

  factory CollabSummary.fromJson(Map<String, dynamic> map) {
    final point = map['downgrade_point'] as Map<String, dynamic>?;
    return CollabSummary(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      encryptionMode: map['encryption_mode'] as String? ?? 'e2e',
      cardCount: (map['card_count'] as num?)?.toInt() ?? 0,
      openCount: (map['open'] as num?)?.toInt() ?? 0,
      doingCount: (map['doing'] as num?)?.toInt() ?? 0,
      needsYouCount: (map['needs_you'] as num?)?.toInt() ?? 0,
      updatedAt:
          map['last_card_updated_at'] as String? ??
          map['updated_at'] as String?,
      causeAddress:
          point?['cause_address'] as String? ??
          (map['roster'] is List ? _hostedCause(map['roster'] as List) : null),
    );
  }

  final String id;
  final String name;
  final String encryptionMode;
  final int cardCount;
  final int openCount;
  final int doingCount;
  final int needsYouCount;
  final String? updatedAt;
  final String? causeAddress;

  bool get isE2e => encryptionMode == 'e2e';
  bool get isActive => openCount > 0;
}

class CollabActivityDay {
  const CollabActivityDay({required this.date, required this.count});

  factory CollabActivityDay.fromJson(Map<String, dynamic> map) {
    return CollabActivityDay(
      date: map['date'] as String? ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }

  final String date;
  final int count;
}

class CollabLaneTotals {
  const CollabLaneTotals({this.backlog = 0, this.doing = 0, this.done = 0});

  factory CollabLaneTotals.fromJson(Map<String, dynamic>? map) {
    if (map == null) return const CollabLaneTotals();
    return CollabLaneTotals(
      backlog: (map['backlog'] as num?)?.toInt() ?? 0,
      doing: (map['doing'] as num?)?.toInt() ?? 0,
      done: (map['done'] as num?)?.toInt() ?? 0,
    );
  }

  final int backlog;
  final int doing;
  final int done;

  int get open => backlog + doing + done;
}

class CollabPortfolioTotals {
  const CollabPortfolioTotals({
    this.collabs = 0,
    this.open = 0,
    this.doing = 0,
    this.needsYou = 0,
  });

  factory CollabPortfolioTotals.fromJson(Map<String, dynamic>? map) {
    if (map == null) return const CollabPortfolioTotals();
    return CollabPortfolioTotals(
      collabs: (map['collabs'] as num?)?.toInt() ?? 0,
      open: (map['open'] as num?)?.toInt() ?? 0,
      doing: (map['doing'] as num?)?.toInt() ?? 0,
      needsYou: (map['needs_you'] as num?)?.toInt() ?? 0,
    );
  }

  final int collabs;
  final int open;
  final int doing;
  final int needsYou;
}

class CollabPortfolio {
  const CollabPortfolio({
    this.activity = const [],
    this.laneTotals = const CollabLaneTotals(),
    this.totals = const CollabPortfolioTotals(),
  });

  factory CollabPortfolio.fromJson(
    Map<String, dynamic>? map,
    List<CollabSummary> collabs,
  ) {
    if (map == null) {
      return CollabPortfolio(
        totals: CollabPortfolioTotals(
          collabs: collabs.length,
          open: collabs.fold(0, (s, c) => s + c.openCount),
          doing: collabs.fold(0, (s, c) => s + c.doingCount),
          needsYou: collabs.fold(0, (s, c) => s + c.needsYouCount),
        ),
      );
    }
    final activityRaw = map['activity'] as List<dynamic>? ?? const [];
    return CollabPortfolio(
      activity: activityRaw
          .map(
            (e) => CollabActivityDay.fromJson(e as Map<String, dynamic>? ?? {}),
          )
          .toList(),
      laneTotals: CollabLaneTotals.fromJson(
        map['lane_totals'] as Map<String, dynamic>?,
      ),
      totals: CollabPortfolioTotals.fromJson(
        map['totals'] as Map<String, dynamic>?,
      ),
    );
  }

  final List<CollabActivityDay> activity;
  final CollabLaneTotals laneTotals;
  final CollabPortfolioTotals totals;
}

class CollabListResult {
  const CollabListResult({required this.collabs, required this.portfolio});

  final List<CollabSummary> collabs;
  final CollabPortfolio portfolio;
}

String? _hostedCause(List<dynamic> roster) {
  for (final e in roster) {
    final m = e as Map<String, dynamic>? ?? {};
    if (m['transport'] == 'mcp') {
      return (m['address'] as String?)?.toLowerCase();
    }
  }
  return null;
}

/// Hub/sidecar may omit `artifacts` or send JSON null — never throw in UI.
List<CollabArtifactView> collabArtifactsFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map)
        CollabArtifactView.fromJson(
          e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
        ),
  ];
}

class CollabDetail {
  const CollabDetail({
    required this.id,
    required this.name,
    required this.encryptionMode,
    required this.lists,
    this.roster = const [],
    this.steererHandles = const [],
    this.cards = const [],
    this.learnings = const [],
    List<CollabArtifactView>? artifacts = const [],
    this.instructions,
    this.memoryThreadId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.causeAddress,
  }) : _artifacts = artifacts;

  factory CollabDetail.fromJson(Map<String, dynamic> map) {
    final listsRaw = map['lists'] as List<dynamic>? ?? const [];
    final rosterRaw = map['roster'] as List<dynamic>? ?? const [];
    final cardsRaw = map['cards'] as List<dynamic>? ?? const [];
    final learnRaw = map['learnings'] as List<dynamic>? ?? const [];
    final steerersRaw = map['steerers'] as List<dynamic>? ?? const [];
    final point = map['downgrade_point'] as Map<String, dynamic>?;
    return CollabDetail(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      encryptionMode: map['encryption_mode'] as String? ?? 'e2e',
      lists:
          listsRaw
              .map(
                (e) =>
                    CollabListView.fromJson(e as Map<String, dynamic>? ?? {}),
              )
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position)),
      roster: rosterRaw
          .map(
            (e) => CollabRosterView.fromJson(e as Map<String, dynamic>? ?? {}),
          )
          .toList(),
      steererHandles: [
        for (final e in steerersRaw)
          if (e is Map && (e['handle'] as String?)?.trim().isNotEmpty == true)
            (e['handle'] as String).trim().toLowerCase(),
      ],
      cards: cardsRaw
          .map((e) => CollabCardView.fromJson(e as Map<String, dynamic>? ?? {}))
          .toList(),
      learnings: learnRaw
          .map(
            (e) =>
                CollabLearningView.fromJson(e as Map<String, dynamic>? ?? {}),
          )
          .toList(),
      artifacts: collabArtifactsFromJson(map['artifacts']),
      instructions: map['instructions'] as String?,
      memoryThreadId: map['memory_thread_id'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
      causeAddress:
          point?['cause_address'] as String? ?? _hostedCause(rosterRaw),
    );
  }

  final String id;
  final String name;
  final String encryptionMode;
  final List<CollabListView> lists;
  final List<CollabRosterView> roster;
  final List<String> steererHandles;
  final List<CollabCardView> cards;
  final List<CollabLearningView> learnings;
  final List<CollabArtifactView>? _artifacts;
  final String? instructions;
  final String? memoryThreadId;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;
  final String? causeAddress;

  /// Empty when omitted, JSON-null, or unsound (hot-reload) null.
  List<CollabArtifactView> get artifacts => _artifacts ?? const [];

  bool get isE2e => encryptionMode == 'e2e';
}

/// One collab artifact — file (blob/resource) or link (url + label).
class CollabArtifactView {
  const CollabArtifactView({
    this.kind = 'file',
    this.label = '',
    this.url = '',
    required this.threadId,
    required this.messageId,
    required this.cardTitle,
    required this.fromHandle,
    required this.createdAt,
    required this.resource,
  });

  factory CollabArtifactView.fromJson(Map<String, dynamic> map) {
    final kind = (map['kind'] as String? ?? 'file').trim().toLowerCase();
    final label = (map['label'] as String? ?? map['title'] as String? ?? '')
        .trim();
    final url = (map['url'] as String? ?? '').trim();
    final resourceMap = Map<String, dynamic>.from(map);
    if ((resourceMap['name'] as String? ?? '').trim().isEmpty) {
      resourceMap['name'] = label.isNotEmpty
          ? label
          : (url.isNotEmpty ? url : 'file');
    }
    return CollabArtifactView(
      kind: kind == 'link' ? 'link' : 'file',
      label: label,
      url: url,
      threadId: map['thread_id'] as String? ?? '',
      messageId: map['message_id'] as String? ?? '',
      cardTitle: map['card_title'] as String? ?? 'Card',
      fromHandle: (map['from_handle'] as String? ?? '').toLowerCase(),
      createdAt: map['created_at'] as String? ?? '',
      resource: BundleResourceView.fromJson(resourceMap),
    );
  }

  final String kind;
  final String label;
  final String url;
  final String threadId;
  final String messageId;
  final String cardTitle;
  final String fromHandle;
  final String createdAt;
  final BundleResourceView resource;

  bool get isLink => kind == 'link';

  String get title {
    if (label.trim().isNotEmpty) return label.trim();
    if (isLink) {
      return url.trim().isNotEmpty ? url.trim() : 'link';
    }
    return resource.name.trim().isNotEmpty ? resource.name : 'file';
  }
}

bool _sameAwaiting(List<AwaitingEntry> a, List<AwaitingEntry> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].address != b[i].address || a[i].actor != b[i].actor) return false;
  }
  return true;
}

class AwaitingEntry {
  const AwaitingEntry({required this.address, required this.actor});

  final String address;
  final String actor;

  factory AwaitingEntry.fromJson(Map<String, dynamic> map) {
    return AwaitingEntry(
      address: (map['address'] as String? ?? '').trim(),
      actor: (map['actor'] as String? ?? 'agent').trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {'address': address, 'actor': actor};

  static List<AwaitingEntry> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AwaitingEntry.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.address.isNotEmpty)
        .toList();
  }
}

class AgentInfo {
  const AgentInfo({
    required this.id,
    required this.slug,
    this.transport,
    this.trustTier,
    this.lastSeen,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> map) {
    // Hub may use `id` or `agent_id`.
    final id = map['id'] as String? ?? map['agent_id'] as String? ?? '';
    return AgentInfo(
      id: id,
      slug: map['slug'] as String? ?? '',
      transport: AgentTransport.tryParse(map['transport'] as String?),
      trustTier: TrustTier.tryParse(map['trust_tier'] as String?),
      lastSeen: _parseDateTime(
        map['last_seen'] ??
            map['capabilities_updated_at'] ??
            map['capability_refreshed_at'],
      ),
    );
  }

  final String id;
  final String slug;

  /// Hub-assigned: `sidecar` | `mcp`. Null when API omits (pre-L1) → hide chip.
  final AgentTransport? transport;

  /// Hub-assigned: `org` | `external` | `enterprise`.
  final TrustTier? trustTier;

  /// Last capability handshake / connect refresh (optional).
  final DateTime? lastSeen;

  /// True when [lastSeen] is within the capability freshness TTL.
  bool get capabilityFresh => isCapabilityFresh(lastSeen);

  AgentInfo copyWith({
    String? id,
    String? slug,
    AgentTransport? transport,
    TrustTier? trustTier,
    DateTime? lastSeen,
  }) {
    return AgentInfo(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      transport: transport ?? this.transport,
      trustTier: trustTier ?? this.trustTier,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

DateTime? _parseDateTime(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
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
  const ContactView({
    required this.handle,
    this.pubkey,
    this.devices = const [],
    this.kind,
    this.avatarUrl,
    this.displayName,
    this.externalLinkId,
    this.linkedAt,
    this.threadId,
  });

  factory ContactView.fromJson(Map<String, dynamic> map) {
    final devicesRaw = map['devices'] as List<dynamic>? ?? const [];
    final avatar = map['avatar_url'] as String?;
    final name = (map['display_name'] as String?)?.trim();
    return ContactView(
      handle: map['handle'] as String? ?? '',
      pubkey: map['pubkey'] as String?,
      devices: devicesRaw
          .map((e) => ContactDeviceView.fromJson(e as Map<String, dynamic>))
          .toList(),
      kind: map['kind'] as String?,
      avatarUrl: (avatar != null && avatar.trim().isNotEmpty)
          ? avatar.trim()
          : null,
      displayName: (name != null && name.isNotEmpty) ? name : null,
      externalLinkId: map['external_link_id'] as String?,
      linkedAt: map['linked_at'] as String?,
      threadId: map['thread_id'] as String?,
    );
  }

  final String handle;
  final String? pubkey;
  final List<ContactDeviceView> devices;
  final String? kind;
  final String? avatarUrl;
  final String? displayName;
  final String? externalLinkId;
  final String? linkedAt;
  final String? threadId;

  bool get isBroadcast => handle.startsWith('@all@') || kind == 'broadcast';
  bool get isExternal => kind == 'external';
}

class PairingPinView {
  const PairingPinView({
    required this.pin,
    required this.handle,
    required this.expiresAt,
    required this.qrUri,
  });

  factory PairingPinView.fromJson(Map<String, dynamic> map) {
    return PairingPinView(
      pin: map['pin'] as String? ?? '',
      handle: map['handle'] as String? ?? '',
      expiresAt: map['expires_at'] as String? ?? '',
      qrUri: map['qr_uri'] as String? ?? '',
    );
  }

  final String pin;
  final String handle;
  final String expiresAt;
  final String qrUri;
}

class PairRequestView {
  const PairRequestView({
    required this.id,
    required this.requesterHandle,
    required this.targetHandle,
    required this.status,
    required this.createdAt,
    this.intro,
  });

  factory PairRequestView.fromJson(Map<String, dynamic> map) {
    return PairRequestView(
      id: map['id'] as String? ?? '',
      requesterHandle: map['requester_handle'] as String? ?? '',
      targetHandle: map['target_handle'] as String? ?? '',
      status: map['status'] as String? ?? '',
      createdAt: map['created_at'] as String? ?? '',
      intro: map['intro'] as String?,
    );
  }

  final String id;
  final String requesterHandle;
  final String targetHandle;
  final String status;
  final String createdAt;
  final String? intro;
}

class PendingPairRequestsView {
  const PendingPairRequestsView({
    this.incoming = const [],
    this.outgoing = const [],
  });

  factory PendingPairRequestsView.fromJson(Map<String, dynamic> map) {
    List<PairRequestView> parse(String key) {
      final raw = map[key] as List<dynamic>? ?? const [];
      return raw
          .map((e) => PairRequestView.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return PendingPairRequestsView(
      incoming: parse('incoming'),
      outgoing: parse('outgoing'),
    );
  }

  final List<PairRequestView> incoming;
  final List<PairRequestView> outgoing;
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

class ThreadDowngradeProposalView {
  const ThreadDowngradeProposalView({
    required this.id,
    required this.threadId,
    required this.proposedSlug,
    required this.status,
    this.prompt,
  });

  factory ThreadDowngradeProposalView.fromJson(
    Map<String, dynamic> map, {
    String? prompt,
  }) {
    final slug = map['proposed_slug'] as String? ?? '';
    return ThreadDowngradeProposalView(
      id: map['id'] as String? ?? '',
      threadId: map['thread_id'] as String? ?? '',
      proposedSlug: slug,
      status: map['status'] as String? ?? 'pending',
      prompt:
          prompt ??
          (slug.isEmpty
              ? null
              : 'Adding @$slug (web) ends E2E for this thread'),
    );
  }

  final String id;
  final String threadId;
  final String proposedSlug;
  final String status;
  final String? prompt;

  bool get isPending => status == 'pending';
}

class PendingTaskApprovalView {
  const PendingTaskApprovalView({
    required this.messageId,
    required this.fromHandle,
    required this.objective,
    required this.prompt,
  });

  factory PendingTaskApprovalView.fromJson(Map<String, dynamic> map) {
    final decision = map['decision'] as Map<String, dynamic>? ?? const {};
    return PendingTaskApprovalView(
      messageId: map['message_id'] as String? ?? '',
      fromHandle: map['from_handle'] as String? ?? '',
      objective: map['objective'] as String? ?? '',
      prompt:
          decision['prompt'] as String? ??
          map['objective'] as String? ??
          'Allow this agent task?',
    );
  }

  final String messageId;
  final String fromHandle;
  final String objective;
  final String prompt;
}

class ThreadDetailResult {
  const ThreadDetailResult({
    required this.id,
    required this.kind,
    required this.status,
    required this.from,
    this.audience = '',
    this.yourStatus,
    this.awaiting = const [],
    this.enterpriseListingId,
    this.pendingDowngrade,
    this.pendingTaskApprovals = const [],
    required this.messages,
  });

  final String id;
  final String kind;
  final String status;
  final String from;
  final String audience;
  final String? yourStatus;
  final List<AwaitingEntry> awaiting;

  /// Hub billing flag — when set, show enterprise warn banner (§7.2).
  final String? enterpriseListingId;

  /// L5 pending unanimous downgrade consent (§6.5).
  final ThreadDowngradeProposalView? pendingDowngrade;

  /// Task gates for non-pre-trusted senders (HumanDecision-style).
  final List<PendingTaskApprovalView> pendingTaskApprovals;

  final List<ThreadMessageView> messages;

  bool get isEnterpriseThread =>
      shouldShowEnterpriseWarnBanner(enterpriseListingId: enterpriseListingId);
}

/// Hub `GET /v1/registry/listing/:idOrAddress` warn payload for compose.
class RegistryListingWarn {
  const RegistryListingWarn({
    required this.listingId,
    required this.address,
    required this.trustTier,
    required this.message,
  });

  factory RegistryListingWarn.fromJson(Map<String, dynamic> map) {
    final listing = map['listing'] as Map<String, dynamic>? ?? const {};
    final warn = map['warn'] as Map<String, dynamic>? ?? const {};
    return RegistryListingWarn(
      listingId: listing['id'] as String? ?? '',
      address: listing['address'] as String? ?? '',
      trustTier:
          TrustTier.tryParse(
            warn['trust_tier'] as String? ?? listing['trust_tier'] as String?,
          ) ??
          TrustTier.enterprise,
      message: warn['message'] as String? ?? kEnterpriseWarnBannerMessage,
    );
  }

  final String listingId;
  final String address;
  final TrustTier trustTier;
  final String message;

  bool get showBanner => trustTier == TrustTier.enterprise;
}

class BundleResourceView {
  const BundleResourceView({
    required this.name,
    this.mime = 'application/octet-stream',
    this.content,
    this.path,
    this.size,
  });

  factory BundleResourceView.fromJson(Map<String, dynamic> map) {
    final name = map['name'] as String? ?? '';
    var mime = map['mime'] as String? ?? map['mime_type'] as String? ?? '';
    if (mime.trim().isEmpty ||
        mime == 'application/octet-stream' ||
        mime == 'binary/octet-stream') {
      final guessed = _guessMimeFromName(name);
      if (guessed != null) mime = guessed;
    }
    if (mime.trim().isEmpty) mime = 'application/octet-stream';

    final sizeRaw = map['size'];
    int? size;
    if (sizeRaw is int) {
      size = sizeRaw;
    } else if (sizeRaw is num) {
      size = sizeRaw.toInt();
    }
    final content = map['content'] as String?;
    if (size == null && content != null && content.isNotEmpty) {
      size = content.length;
    }
    return BundleResourceView(
      name: name,
      mime: mime,
      content: content,
      path: map['path'] as String?,
      size: size,
    );
  }

  static String? _guessMimeFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return null;
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'md':
      case 'markdown':
        return 'text/markdown';
      case 'txt':
      case 'text':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'xml':
        return 'application/xml';
      case 'yaml':
      case 'yml':
      case 'toml':
        return 'text/plain';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      default:
        return null;
    }
  }

  final String name;
  final String mime;
  final String? content;
  final String? path;
  final int? size;

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get hasPath => path != null && path!.trim().isNotEmpty;
  bool get hasContent => content != null && content!.trim().isNotEmpty;

  /// Local file or inline text the UI can show / open.
  bool get isAvailable => hasPath || hasContent;

  bool get isImage {
    final m = mime.toLowerCase();
    if (m.startsWith('image/')) {
      return m.contains('png') ||
          m.contains('jpeg') ||
          m.contains('jpg') ||
          m.contains('gif') ||
          m.contains('webp');
    }
    return const {'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(extension);
  }

  bool get isVideo {
    final m = mime.toLowerCase();
    if (m.startsWith('video/')) {
      return m.contains('mp4') ||
          m.contains('quicktime') ||
          m.contains('webm') ||
          m == 'video/mov';
    }
    return const {'mp4', 'mov', 'webm'}.contains(extension);
  }

  bool get isText {
    final m = mime.toLowerCase();
    if (m.startsWith('text/')) return true;
    if (m == 'application/json' ||
        m == 'application/xml' ||
        m.endsWith('+json') ||
        m.endsWith('+xml')) {
      return true;
    }
    return const {
      'md',
      'markdown',
      'txt',
      'text',
      'json',
      'csv',
      'xml',
      'yaml',
      'yml',
      'toml',
    }.contains(extension);
  }

  bool get isPdf {
    final m = mime.toLowerCase();
    return m == 'application/pdf' || extension == 'pdf';
  }

  String get kindLabel {
    if (isImage) return 'Image';
    if (isVideo) return 'Video';
    if (isPdf) return 'PDF';
    if (isText) return 'Text';
    if (mime.isNotEmpty && mime != 'application/octet-stream') return mime;
    if (extension.isNotEmpty) return extension.toUpperCase();
    return 'File';
  }

  String? get sizeLabel {
    final n = size;
    if (n == null || n < 0) return null;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) {
      final kb = n / 1024;
      return kb >= 10 ? '${kb.round()} KB' : '${kb.toStringAsFixed(1)} KB';
    }
    final mb = n / (1024 * 1024);
    return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
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
    this.resources = const [],
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

  /// Opened file attachments (`resources[]` with optional `path` / `content`).
  final List<BundleResourceView> resources;
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
      resources: resources,
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
    if (resources.isNotEmpty) return false;
    return _contentParts.isEmpty;
  }

  /// Notes that only describe materialization / stubs — shown via attachment UI.
  static bool isArtifactPlumbingNote(String notes) {
    final n = notes.trim().toLowerCase();
    if (n.isEmpty) return false;
    return n.contains('too large to inline') ||
        n.contains('resource.content is standard base64') ||
        n.contains('content not inlined') ||
        n.contains('artifact available on this device') ||
        n.contains('opened encrypted blob') ||
        (n.startsWith('binary artifact') && n.contains('bytes'));
  }

  String? get _displayNotes {
    final notes = bundleNotes?.trim();
    if (notes == null || notes.isEmpty) return null;
    if (resources.isNotEmpty && isArtifactPlumbingNote(notes)) return null;
    // Drop plumbing lines when mixed with real notes.
    final kept = notes
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty && !isArtifactPlumbingNote(l))
        .toList();
    if (kept.isEmpty) return null;
    return kept.join('\n');
  }

  List<String> get _contentParts => [
    if (bundleSubject != null && bundleSubject!.trim().isNotEmpty)
      bundleSubject!.trim(),
    if (_displayNotes != null) _displayNotes!,
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
    if (parts.isEmpty) {
      if (resources.isNotEmpty) return '';
      return 'No message body';
    }
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
      return fromHandle.substring(slash + 1).toLowerCase();
    }
    return fromHandle.toLowerCase();
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
    this.pubkey,
  });

  factory SafetyNumberResult.fromJson(Map<String, dynamic> map) {
    return SafetyNumberResult(
      handle: map['handle'] as String? ?? '',
      fingerprint: map['fingerprint'] as String? ?? '',
      uri: map['uri'] as String? ?? '',
      verified: map['verified'] as bool?,
      pubkey: map['pubkey'] as String?,
    );
  }

  final String handle;
  final String fingerprint;
  final String uri;
  final bool? verified;

  /// Hex-encoded X25519 device public key (own device only).
  final String? pubkey;
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

/// User-facing copy for daemon/hub failures — never raw exception dumps.
String friendlyDaemonError(Object error, {String what = 'That'}) {
  var msg = error.toString().trim();
  for (final prefix in const [
    'DaemonException: ',
    'ClientException: ',
    'HttpException: ',
    'Exception: ',
  ]) {
    if (msg.startsWith(prefix)) {
      msg = msg.substring(prefix.length).trim();
    }
  }
  if (msg.startsWith('TimeoutException')) {
    msg = 'timed out';
  }
  final lower = msg.toLowerCase();
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return '$what took too long. Try again in a moment.';
  }
  if (isLocalCourierTransportFailure(lower)) {
    return "Can't reach the local mutande daemon. Open Settings and tap Check daemon.";
  }
  if (isHubAuthFailure(lower)) {
    return 'Sign-in expired or was rejected. Open Settings and sign in again.';
  }
  if (isHubUnimplemented(lower)) {
    if (what.toLowerCase().contains('collab')) {
      return "This hub doesn't support collab yet.";
    }
    return "Couldn't load $what. This isn't available on the hub yet.";
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return "Couldn't load $what. Retry.";
  }
  if (lower.contains('500') || lower.contains('502') || lower.contains('503')) {
    return "Couldn't reach the hub. Try again in a moment.";
  }
  if (_looksLikeRawException(msg)) {
    return "Couldn't load $what. Try again in a moment.";
  }
  return msg;
}

bool _looksLikeRawException(String msg) {
  final lower = msg.toLowerCase();
  return lower.contains('exception') ||
      lower.contains('uri=') ||
      lower.contains('stack trace') ||
      lower.contains('errno =') ||
      lower.contains('/v1/') ||
      lower.contains('hub.mutande') ||
      lower.contains('jsonrpc') ||
      RegExp(r'\b(get|post|put|patch|delete)\s+/').hasMatch(lower) ||
      RegExp(r'https?://').hasMatch(lower);
}
