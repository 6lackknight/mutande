import 'dart:async';
import 'dart:io';

import 'daemon_client.dart';

/// Starts and stops the bundled `mutande-core serve` sidecar.
///
/// Path resolution order ([defaultResolvePath]):
/// 1. `MUTANDE_CORE_PATH` env
/// 2. App bundle / beside executable ([bundledResolvePath])
/// 3. Dev fallbacks: `../core/target/release|debug/mutande-core`
/// 4. `mutande-core` on PATH
///
/// [restart] / version-mismatch replace prefer [bundledResolvePath] so a stale
/// env or PATH binary cannot win over `Contents/Resources/mutande-core`.
class CoreSidecar {
  CoreSidecar({
    DaemonClient? daemon,
    this.resolvePath,
    this.spawnServe,
    this.killPortListeners,
    this.expectedVersion,
    // Keychain identity bootstrap on macOS can take well over 20s.
    this.healthTimeout = const Duration(seconds: 60),
  }) : _daemon = daemon ?? DaemonClient();

  final DaemonClient _daemon;
  final String? Function()? resolvePath;
  final Future<Process> Function(String corePath)? spawnServe;
  final Future<void> Function(int port)? killPortListeners;
  final Duration healthTimeout;

  /// App semver (e.g. `1.0.9`). When set, a healthy daemon with a different
  /// (or missing) version is replaced by the bundled binary.
  final String? expectedVersion;

  Process? _process;
  bool _startedByUs = false;

  /// Absolute path chosen for this session (after [start]).
  String? resolvedPath;

  /// Strip `+build` / whitespace for semver compare.
  static String? normalizeVersion(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.split('+').first.trim();
  }

  /// True when [daemonVersion] matches [expected] (both normalized).
  static bool versionsMatch(String? daemonVersion, String? expected) {
    final want = normalizeVersion(expected);
    if (want == null) return true;
    final got = normalizeVersion(daemonVersion);
    return got != null && got == want;
  }

  static String get _exeName =>
      Platform.isWindows ? 'mutande-core.exe' : 'mutande-core';

  /// Sidecar next to / inside the running app (Resources or beside exe).
  /// Ignores `MUTANDE_CORE_PATH` and PATH.
  static String? bundledResolvePath() {
    try {
      final exe = File(Platform.resolvedExecutable).absolute;
      final exeDir = exe.parent;

      if (Platform.isMacOS) {
        final contents = exeDir.parent; // …/Contents
        final resources = File('${contents.path}/Resources/$_exeName');
        if (resources.existsSync()) return resources.path;
      }

      final beside = File('${exeDir.path}/$_exeName');
      if (beside.existsSync()) return beside.path;
    } catch (_) {
      // ignore — fall through
    }
    return null;
  }

  static String? defaultResolvePath() {
    final env = Platform.environment['MUTANDE_CORE_PATH']?.trim();
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return File(env).absolute.path;
    }

    final bundled = bundledResolvePath();
    if (bundled != null) return bundled;

    final exeName = _exeName;
    final cwd = Directory.current.path;
    for (final rel in [
      '../core/target/release/$exeName',
      '../core/target/debug/$exeName',
      'core/target/release/$exeName',
      'core/target/debug/$exeName',
      '../core/target/x86_64-pc-windows-msvc/release/$exeName',
    ]) {
      final f = File('$cwd/$rel');
      if (f.existsSync()) return f.absolute.path;
    }

    return _which(exeName) ??
        (Platform.isWindows ? _which('mutande-core') : null);
  }

  static String? _which(String name) {
    try {
      final result = Platform.isWindows
          ? Process.runSync('where', [name], runInShell: true)
          : Process.runSync('which', [name]);
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim().split('\n').first.trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  int get _httpPort {
    final uri = Uri.tryParse(_daemon.httpBaseUrl);
    if (uri?.hasPort == true) return uri!.port;
    return 3847;
  }

  String? _resolvePath({required bool preferBundled}) {
    if (resolvePath != null) return resolvePath!();
    if (preferBundled) {
      // Installed app: Resources/beside. Dev: fall back to target/ or env.
      return bundledResolvePath() ?? defaultResolvePath();
    }
    return defaultResolvePath();
  }

  /// Ensure daemon is up. Spawns sidecar if health check fails.
  ///
  /// Replaces a healthy but version-mismatched daemon (stale `flutter run` /
  /// previous DMG still holding :3847). Does not kill a matching daemon that
  /// is still coming up (Keychain) — only replaces when health answers with a
  /// wrong/missing version.
  Future<CoreSidecarStartResult> start({bool preferBundled = false}) async {
    var useBundled = preferBundled;
    var path = _resolvePath(preferBundled: useBundled);
    resolvedPath = path;

    final health = await _daemon.pingHealth();
    if (health.connected) {
      if (versionsMatch(health.version, expectedVersion)) {
        if (path != null) {
          await _persistCorePath(path);
        }
        return CoreSidecarStartResult(
          alreadyRunning: true,
          path: path,
        );
      }
      // Wrong binary on the port — free it, then spawn the app's sidecar.
      await _stopListeningDaemon();
      useBundled = true;
      path = _resolvePath(preferBundled: true);
      resolvedPath = path;
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
    if (ready == null) {
      // Do not stop — the user may still be completing a Keychain prompt.
      return CoreSidecarStartResult(
        alreadyRunning: false,
        path: path,
        error: 'daemon did not become healthy within ${healthTimeout.inSeconds}s',
        stillStarting: true,
      );
    }

    // Kill/spawn succeeded but the binary we started is still the wrong
    // version (stale Contents/Resources or outdated cargo target). Restart
    // cannot fix that — surface a clear reinstall/rebuild hint.
    if (!versionsMatch(ready.version, expectedVersion)) {
      final got = normalizeVersion(ready.version) ?? 'unknown';
      final want = normalizeVersion(expectedVersion) ?? expectedVersion!;
      return CoreSidecarStartResult(
        alreadyRunning: false,
        path: path,
        error: 'Bundled courier is v$got but app expects v$want. '
            'Reinstall mutande (or rebuild Resources/mutande-core) — '
            'Restart cannot replace a stale sidecar inside the app.',
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

  Future<DaemonHealthResult?> _waitHealthy() async {
    final deadline = DateTime.now().add(healthTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final health = await _daemon.pingHealth();
      if (health.connected) return health;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  Future<bool> _waitUntilDown() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final health = await _daemon.pingHealth();
      if (!health.connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// Stop only the process we spawned (leave externally started daemons alone).
  Future<void> stop() async {
    if (!_startedByUs) return;
    await _stopSpawnedProcess();
  }

  /// Kill whatever holds the HTTP port, then start the app-bundled sidecar.
  ///
  /// User-initiated — may interrupt Keychain unlock; [stillStarting] on the
  /// result means unlock may still be needed (we do not kill again).
  Future<CoreSidecarStartResult> restart() async {
    await _stopListeningDaemon();
    return start(preferBundled: true);
  }

  /// Free the HTTP port: our child first, then any external mutande-core serve.
  Future<void> _stopListeningDaemon() async {
    await _stopSpawnedProcess();
    _daemon.invalidateHttpToken();

    final stillUp = await _daemon.pingHealth();
    if (!stillUp.connected) return;

    final kill = killPortListeners ?? defaultKillPortListeners;
    try {
      await kill(_httpPort);
    } catch (_) {
      // Best-effort — caller will surface spawn/bind failures.
    }
    _daemon.invalidateHttpToken();
    await _waitUntilDown();
  }

  Future<void> _stopSpawnedProcess() async {
    final proc = _process;
    _process = null;
    _startedByUs = false;
    if (proc == null) return;
    if (Platform.isWindows) {
      proc.kill(ProcessSignal.sigkill);
      return;
    }
    proc.kill(ProcessSignal.sigterm);
    try {
      await proc.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      proc.kill(ProcessSignal.sigkill);
    }
  }

  /// Kill processes listening on [port] (stale courier from a prior install).
  static Future<void> defaultKillPortListeners(int port) async {
    if (Platform.isWindows) {
      await _killPortListenersWindows(port);
      return;
    }
    final result = await Process.run(
      'lsof',
      ['-nP', '-iTCP:$port', '-sTCP:LISTEN', '-t'],
    );
    if (result.exitCode != 0) return;
    final pids = (result.stdout as String)
        .split(RegExp(r'\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final pid in pids) {
      await Process.run('kill', ['-TERM', pid]);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final pid in pids) {
      await Process.run('kill', ['-KILL', pid]);
    }
  }

  static Future<void> _killPortListenersWindows(int port) async {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        'Get-NetTCPConnection -LocalPort $port -State Listen '
            '-ErrorAction SilentlyContinue | '
            'Select-Object -ExpandProperty OwningProcess -Unique',
      ],
    );
    if (result.exitCode != 0) return;
    final pids = (result.stdout as String)
        .split(RegExp(r'\s+'))
        .map((s) => s.trim())
        .where((s) => RegExp(r'^\d+$').hasMatch(s))
        .toSet();
    for (final pid in pids) {
      await Process.run('taskkill', ['/PID', pid, '/F']);
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
    this.stillStarting = false,
  });

  final bool alreadyRunning;
  final String? path;
  final String? error;

  /// Spawned process may still come up (e.g. Keychain unlock in progress).
  final bool stillStarting;

  bool get ok => error == null;
}
