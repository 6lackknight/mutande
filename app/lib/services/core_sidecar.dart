import 'dart:async';
import 'dart:io';

import 'daemon_client.dart';

/// Starts and stops the bundled `mutande-core serve` sidecar.
///
/// Path resolution order:
/// 1. `MUTANDE_CORE_PATH` env
/// 2. macOS app bundle `Contents/Resources/mutande-core`
/// 3. Sibling of the Flutter executable (`…/MacOS/mutande-core`)
/// 4. Dev fallbacks: `../core/target/release|debug/mutande-core`
/// 5. `mutande-core` on PATH
class CoreSidecar {
  CoreSidecar({
    DaemonClient? daemon,
    this.resolvePath,
    this.spawnServe,
    // Keychain identity bootstrap on macOS can take several seconds.
    this.healthTimeout = const Duration(seconds: 20),
  }) : _daemon = daemon ?? DaemonClient();

  final DaemonClient _daemon;
  final String? Function()? resolvePath;
  final Future<Process> Function(String corePath)? spawnServe;
  final Duration healthTimeout;

  Process? _process;
  bool _startedByUs = false;

  /// Absolute path chosen for this session (after [start]).
  String? resolvedPath;

  static String? defaultResolvePath() {
    final env = Platform.environment['MUTANDE_CORE_PATH']?.trim();
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return File(env).absolute.path;
    }

    // macOS bundle: Contents/MacOS/<app> → Contents/Resources/mutande-core
    try {
      final exe = File(Platform.resolvedExecutable).absolute;
      final macosDir = exe.parent; // …/Contents/MacOS
      final contents = macosDir.parent; // …/Contents
      final resources = File('${contents.path}/Resources/mutande-core');
      if (resources.existsSync()) return resources.path;
      final beside = File('${macosDir.path}/mutande-core');
      if (beside.existsSync()) return beside.path;
    } catch (_) {
      // ignore — fall through
    }

    // Dev: run from app/ → ../core/target/{release,debug}/mutande-core
    final cwd = Directory.current.path;
    for (final rel in [
      '../core/target/release/mutande-core',
      '../core/target/debug/mutande-core',
      'core/target/release/mutande-core',
      'core/target/debug/mutande-core',
    ]) {
      final f = File('$cwd/$rel');
      if (f.existsSync()) return f.absolute.path;
    }

    return _which('mutande-core');
  }

  static String? _which(String name) {
    try {
      final result = Process.runSync('which', [name]);
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  /// Ensure daemon is up. Spawns sidecar if health check fails.
  Future<CoreSidecarStartResult> start() async {
    final path = (resolvePath ?? defaultResolvePath)();
    resolvedPath = path;

    final health = await _daemon.pingHealth();
    if (health.connected) {
      // Still persist path when we know it — Connect AI needs an absolute binary.
      if (path != null) {
        await _persistCorePath(path);
      }
      return CoreSidecarStartResult(
        alreadyRunning: true,
        path: path,
      );
    }

    if (path == null) {
      return CoreSidecarStartResult(
        alreadyRunning: false,
        error: 'mutande-core not found '
            '(set MUTANDE_CORE_PATH or bundle Resources/mutande-core)',
      );
    }

    try {
      final spawn = spawnServe ?? _defaultSpawn;
      _process = await spawn(path);
      _startedByUs = true;
    } catch (e) {
      return CoreSidecarStartResult(
        alreadyRunning: false,
        path: path,
        error: 'failed to spawn mutande-core: $e',
      );
    }

    final ready = await _waitHealthy();
    if (!ready) {
      await stop();
      return CoreSidecarStartResult(
        alreadyRunning: false,
        path: path,
        error: 'daemon did not become healthy within ${healthTimeout.inSeconds}s',
      );
    }

    await _persistCorePath(path);
    return CoreSidecarStartResult(alreadyRunning: false, path: path);
  }

  Future<void> _persistCorePath(String path) async {
    try {
      await _daemon.setCorePath(path);
    } catch (_) {
      // Non-fatal — connect_host still has MUTANDE_CORE_PATH / which fallbacks.
    }
  }

  Future<Process> _defaultSpawn(String corePath) async {
    final process = await Process.start(
      corePath,
      const ['serve'],
      environment: {
        ...Platform.environment,
        'MUTANDE_CORE_PATH': corePath,
      },
      mode: ProcessStartMode.normal,
    );
    // Prevent pipe-buffer deadlock if the daemon logs heavily.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return process;
  }

  Future<bool> _waitHealthy() async {
    final deadline = DateTime.now().add(healthTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final health = await _daemon.pingHealth();
      if (health.connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// Stop only the process we spawned (leave externally started daemons alone).
  Future<void> stop() async {
    if (!_startedByUs) return;
    final proc = _process;
    _process = null;
    _startedByUs = false;
    if (proc == null) return;
    proc.kill(ProcessSignal.sigterm);
    try {
      await proc.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      proc.kill(ProcessSignal.sigkill);
    }
  }

  void dispose() {
    _daemon.dispose();
  }
}

class CoreSidecarStartResult {
  const CoreSidecarStartResult({
    required this.alreadyRunning,
    this.path,
    this.error,
  });

  final bool alreadyRunning;
  final String? path;
  final String? error;

  bool get ok => error == null;
}
