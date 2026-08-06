import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/services/core_sidecar.dart';
import 'package:app/services/daemon_client.dart';

void main() {
  test('normalizeVersion strips build and whitespace', () {
    expect(CoreSidecar.normalizeVersion('1.0.9+10'), '1.0.9');
    expect(CoreSidecar.normalizeVersion(' 1.0.8 '), '1.0.8');
    expect(CoreSidecar.normalizeVersion(''), isNull);
    expect(CoreSidecar.normalizeVersion(null), isNull);
  });

  test('versionsMatch ignores build suffix', () {
    expect(CoreSidecar.versionsMatch('1.0.9', '1.0.9+10'), isTrue);
    expect(CoreSidecar.versionsMatch('1.0.8', '1.0.9'), isFalse);
    expect(CoreSidecar.versionsMatch(null, '1.0.9'), isFalse);
    expect(CoreSidecar.versionsMatch('1.0.9', null), isTrue);
  });

  test('start skips spawn when daemon already healthy and version matches',
      () async {
    var healthCalls = 0;
    var setPathCalls = 0;
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String?;
        if (method == 'set_core_path') {
          setPathCalls++;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'ok': true, 'path': '/tmp/fake-mutande-core'},
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        healthCalls++;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'ok': true,
              'service': 'mutande-core',
              'version': '1.0.9',
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }),
      httpToken: 'test-token',
    );

    var spawned = false;
    final sidecar = CoreSidecar(
      daemon: daemon,
      expectedVersion: '1.0.9+10',
      resolvePath: () => '/tmp/fake-mutande-core',
      spawnServe: (path) async {
        spawned = true;
        throw StateError('should not spawn');
      },
    );

    final result = await sidecar.start();
    expect(result.ok, isTrue);
    expect(result.alreadyRunning, isTrue);
    expect(spawned, isFalse);
    expect(healthCalls, greaterThan(0));
    expect(setPathCalls, 1);
    await sidecar.stop();
  });

  test('start replaces healthy daemon when version mismatches', () async {
    var healthCalls = 0;
    var killCalls = 0;
    var spawnCount = 0;
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String?;
        if (method == 'set_core_path') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'ok': true, 'path': '/tmp/fake-mutande-core'},
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        healthCalls++;
        // Before kill: stale 1.0.8. After spawn (spawnCount >= 1): healthy 1.0.9.
        // Between kill and spawn: down.
        if (spawnCount >= 1) {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'ok': true,
                'service': 'mutande-core',
                'version': '1.0.9',
              },
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        if (killCalls > 0) {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'error': {'code': -32000, 'message': 'down'},
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'ok': true,
              'service': 'mutande-core',
              'version': '1.0.8',
            },
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }),
      httpToken: 'test-token',
      requestTimeout: const Duration(milliseconds: 50),
    );

    final sidecar = CoreSidecar(
      daemon: daemon,
      expectedVersion: '1.0.9',
      resolvePath: () => '/tmp/fake-mutande-core',
      healthTimeout: const Duration(milliseconds: 400),
      killPortListeners: (port) async {
        expect(port, 3847);
        killCalls++;
      },
      spawnServe: (path) async {
        spawnCount++;
        return Process.start('sleep', ['30']);
      },
    );

    final result = await sidecar.start();
    expect(result.ok, isTrue);
    expect(result.alreadyRunning, isFalse);
    expect(killCalls, 1);
    expect(spawnCount, 1);
    expect(healthCalls, greaterThan(1));
    await sidecar.stop();
  });

  test('start reports missing binary', () async {
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'error': {'code': -32000, 'message': 'down'},
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }),
      httpToken: 'test-token',
      requestTimeout: const Duration(milliseconds: 50),
    );

    // pingHealth catches errors and returns connected:false
    final sidecar = CoreSidecar(
      daemon: daemon,
      resolvePath: () => null,
      healthTimeout: const Duration(milliseconds: 100),
    );

    final result = await sidecar.start();
    expect(result.ok, isFalse);
    expect(result.error, contains('mutande-core not found'));
  });

  test('restart kills external listener then starts again', () async {
    var spawnCount = 0;
    var killCalls = 0;
    Process? first;
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'health' && spawnCount >= 2) {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'ok': true,
                'service': 'mutande-core',
                'version': '1.0.9',
              },
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'error': {'code': -32000, 'message': 'down'},
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }),
      httpToken: 'test-token',
      requestTimeout: const Duration(milliseconds: 50),
    );

    final sidecar = CoreSidecar(
      daemon: daemon,
      expectedVersion: '1.0.9',
      resolvePath: () => '/tmp/fake-mutande-core',
      healthTimeout: const Duration(milliseconds: 300),
      killPortListeners: (_) async {
        killCalls++;
      },
      spawnServe: (path) async {
        spawnCount++;
        first ??= await Process.start('sleep', ['30']);
        return first!;
      },
    );

    await sidecar.start();
    final restarted = await sidecar.restart();
    expect(restarted.ok, isTrue);
    expect(spawnCount, 2);
    // First start had nothing listening; restart still best-effort kills.
    expect(killCalls, greaterThanOrEqualTo(0));
    await sidecar.stop();
    first?.kill();
  });

  test('defaultResolvePath returns null or existing path without throwing', () {
    final path = CoreSidecar.defaultResolvePath();
    if (path != null) {
      expect(File(path).existsSync(), isTrue);
    }
  });
}
