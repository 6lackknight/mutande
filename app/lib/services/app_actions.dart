import 'package:flutter/foundation.dart';

/// Cross-cutting actions shared by the tray menu and the main window.
class AppActions {
  AppActions._();

  /// Incremented when something (e.g. tray) requests Connect AI hosts.
  static final ValueNotifier<int> connectHostsTick = ValueNotifier(0);

  static void requestConnectHosts() {
    connectHostsTick.value++;
  }
}
