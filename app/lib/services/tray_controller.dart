import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_actions.dart';
import 'daemon_client.dart';

/// macOS menu-bar (status item) controller.
///
/// Owns the tray icon/menu and polls daemon health for a cheap status line.
/// Window show/hide goes through [window_manager]; quit tears down tray + exits.
class TrayController with TrayListener, WindowListener {
  TrayController({
    DaemonClient? daemon,
    this.healthPollInterval = const Duration(seconds: 30),
  }) : _daemon = daemon ?? DaemonClient();

  static const iconAsset = 'assets/tray_icon.png';

  final DaemonClient _daemon;
  final Duration healthPollInterval;

  Timer? _healthTimer;
  bool? _daemonUp;
  bool _started = false;

  Future<void> start() async {
    if (_started || kIsWeb || !Platform.isMacOS) return;
    _started = true;

    trayManager.addListener(this);
    windowManager.addListener(this);

    await trayManager.setIcon(iconAsset, isTemplate: true);
    await trayManager.setToolTip('Mutande');
    await _refreshMenu();

    unawaited(_pollHealth());
    _healthTimer = Timer.periodic(healthPollInterval, (_) {
      unawaited(_pollHealth());
    });
  }

  Future<void> dispose() async {
    _healthTimer?.cancel();
    _healthTimer = null;
    if (_started) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      await trayManager.destroy();
    }
    _daemon.dispose();
    _started = false;
  }

  Future<void> _pollHealth() async {
    final result = await _daemon.pingHealth();
    final up = result.connected;
    if (_daemonUp == up) return;
    _daemonUp = up;
    await _refreshMenu();
  }

  Future<void> _refreshMenu() async {
    final statusLabel = _daemonUp == null
        ? 'Daemon: …'
        : _daemonUp!
            ? 'Daemon: up'
            : 'Daemon: down';

    final menu = Menu(
      items: [
        MenuItem(key: 'status', label: statusLabel, disabled: true),
        MenuItem.separator(),
        MenuItem(key: 'open', label: 'Open Mutande'),
        MenuItem(key: 'connect_hosts', label: 'Connect AI hosts'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  Future<void> showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    _healthTimer?.cancel();
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        unawaited(showMainWindow());
      case 'connect_hosts':
        unawaited(showMainWindow());
        AppActions.requestConnectHosts();
      case 'quit':
        unawaited(_quit());
    }
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }
}
