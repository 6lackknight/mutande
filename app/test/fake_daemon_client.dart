import 'dart:async';

import 'package:app/services/daemon_client.dart';
import 'package:app/services/daemon_errors.dart';
import 'package:app/services/daemon_rpc_catalog.g.dart';

/// One in-memory RPC invocation recorded by [FakeDaemonClient].
class FakeRpcCall {
  const FakeRpcCall(this.method, this.params);

  final String method;
  final Map<String, dynamic>? params;
}

typedef FakeRpcHandler =
    FutureOr<dynamic> Function(Map<String, dynamic>? params);

/// In-memory daemon adapter: skips HTTP/JSON-RPC. Handlers return the RPC
/// *result* object (the same map [DaemonClient] methods already parse).
class FakeDaemonClient {
  FakeDaemonClient({
    Map<String, FakeRpcHandler>? handlers,
    this.fallback,
    this.defaults = true,
  }) : handlers = {...?handlers};

  final Map<String, FakeRpcHandler> handlers;
  final FutureOr<dynamic> Function(
    String method,
    Map<String, dynamic>? params,
  )?
  fallback;
  final bool defaults;
  final List<FakeRpcCall> calls = [];

  void on(String method, FakeRpcHandler handler) {
    handlers[method] = handler;
  }

  void result(String method, Object? value) {
    handlers[method] = (_) => value;
  }

  void error(String method, String message) {
    handlers[method] = (_) => throw DaemonException(message);
  }

  DaemonClient client() {
    return DaemonClient(
      httpToken: 'test-token',
      requestTimeout: const Duration(seconds: 2),
      invokeRpc: handle,
    );
  }

  Future<dynamic> handle(String method, Map<String, dynamic>? params) async {
    calls.add(FakeRpcCall(method, params));
    final handler = handlers[method];
    if (handler != null) {
      return handler(params);
    }
    if (fallback != null) {
      return fallback!(method, params);
    }
    if (defaults) {
      final canned = _defaultResult(method);
      if (canned != null) return canned;
    }
    throw DaemonException('unhandled RPC $method');
  }

  static dynamic _defaultResult(String method) {
    switch (method) {
      case 'list_threads':
        return {'threads': <dynamic>[]};
      case 'list_collabs':
        return {'collabs': <dynamic>[], 'portfolio': <String, dynamic>{}};
      case 'list_contacts':
      case 'list_external_contacts':
        return {'contacts': <dynamic>[]};
      case 'list_agents':
        return {'agents': <dynamic>[]};
      case 'health':
        return {'ok': true, 'service': 'mutande-core', 'version': 'test'};
      case 'get_status':
      case 'me':
        return {
          'signed_in': true,
          'needs_onboarding': false,
          'configured': true,
          'handle': 'alice@acme',
        };
      default:
        if (daemonRpcCatalog[method]?.kind == 'stub') {
          throw DaemonException('removed method $method');
        }
        return null;
    }
  }
}

/// Convenience for tests that switch on method name and return RPC results.
DaemonClient rpcDaemon(
  FutureOr<dynamic> Function(String method, Map<String, dynamic>? params)
  onCall, {
  Duration timeout = const Duration(seconds: 2),
}) {
  return DaemonClient(
    httpToken: 'test-token',
    requestTimeout: timeout,
    invokeRpc: (method, params) async => onCall(method, params),
  );
}
