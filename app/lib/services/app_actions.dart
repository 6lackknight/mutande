import 'package:flutter/foundation.dart';

/// Cross-cutting actions shared by the tray menu and the main window.
class AppActions {
  AppActions._();

  /// Incremented when something (e.g. tray) requests Connect AI hosts.
  static final ValueNotifier<int> connectHostsTick = ValueNotifier(0);

  /// When set, Home opens Threads on this id (then cleared by the handler).
  static final ValueNotifier<String?> openThreadRequest = ValueNotifier(null);

  static void requestConnectHosts() {
    connectHostsTick.value++;
  }

  static void requestOpenThread(String threadId) {
    final id = threadId.trim();
    if (id.isEmpty) return;
    openThreadRequest.value = id;
  }
}
