import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
/// | `get_status` / `me` | Configured?, handle/org from hub when JWT present |
/// | `register` / `onboard` | Invite + handle + hub_url → persist JWT |
/// | `list_contacts` | Org members + synthetic `@all@org` |
/// | `list_threads` | Filter: `needs_action`, `open`, `closed` |
/// | `get_thread` | Thread + messages with decrypted `bundle` (or `open_error` without ciphertext) |
/// | `get_draft` | Current self-draft (plain after hub sync) |
/// | `draft_add_question` | Merge human decision into draft |
/// | `draft_add_resource` | Merge resource request into draft |
/// | `forward_draft` | Send draft to recipient; opens thread |
/// | `reply_to_thread` | Encrypted reply on existing thread |
/// | `close_thread` | Mark thread closed |
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
    this.requestTimeout = const Duration(seconds: 3),
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
  Future<DaemonStatusResult> getStatus() async {
    final result = await _call('get_status');
    final map = result as Map<String, dynamic>? ?? {};
    return DaemonStatusResult(
      configured: map['configured'] == true,
      hubUrl: map['hub_url'] as String?,
      handle: map['handle'] as String?,
      orgId: map['org_id'] as String?,
    );
  }

  /// Accept invite and register device pubkey via JSON-RPC `register`
  /// (alias `onboard`).
  Future<OnboardResult> register({
    required String inviteCode,
    required String handle,
    required String hubUrl,
  }) async {
    final result = await _call('register', {
      'invite_code': inviteCode,
      'handle': handle,
      'hub_url': hubUrl,
    });
    final map = result as Map<String, dynamic>? ?? {};
    return OnboardResult(
      handle: map['handle'] as String? ?? handle,
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
          note: m['note'] as String?,
        );
      }).toList(),
    );
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
        .timeout(requestTimeout);

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

  static String _expandHome(String path) {
    if (path == '~') {
      return Platform.environment['HOME'] ?? path;
    }
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        return path;
      }
      return '$home/${path.substring(2)}';
    }
    return path;
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
    this.hubUrl,
    this.handle,
    this.orgId,
  });

  final bool configured;
  final String? hubUrl;
  final String? handle;
  final String? orgId;
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
}

class HostWriteResult {
  const HostWriteResult({
    required this.host,
    required this.path,
    required this.ok,
    this.note,
  });

  final String host;
  final String path;
  final bool ok;
  final String? note;
}

class DaemonException implements Exception {
  DaemonException(this.message);
  final String message;

  @override
  String toString() => 'DaemonException: $message';
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
