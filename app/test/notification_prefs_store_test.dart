import 'package:app/services/notification_prefs_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('thread inspector defaults visible', () {
    expect(const NotificationPrefs().threadInspectorVisible, isTrue);
    expect(NotificationPrefs.fromJson(const {}).threadInspectorVisible, isTrue);
  });

  test('thread inspector json roundtrip', () async {
    final hidden = NotificationPrefs.fromJson(const {
      'thread_inspector_visible': false,
    });
    expect(hidden.threadInspectorVisible, isFalse);
    expect(hidden.toJson()['thread_inspector_visible'], isFalse);

    final store = NotificationPrefsStore.memory();
    await store.update((p) => p.copyWith(threadInspectorVisible: false));
    expect(store.current.threadInspectorVisible, isFalse);

    await store.update((p) => p.copyWith(enabled: false));
    expect(store.current.threadInspectorVisible, isFalse);
  });
}
