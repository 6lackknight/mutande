import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/daemon_client.dart';
import 'package:app/services/thread_list_cache_store.dart';

void main() {
  test('ThreadListCacheStore round-trips summaries', () async {
    final dir = Directory.systemTemp.createTempSync('mutande-thread-cache-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/thread_list_cache.json';
    final store = ThreadListCacheStore(path: path);
    const threads = [
      ThreadSummary(
        id: 't1',
        kind: 'direct',
        status: 'open',
        from: 'alice@acme',
        audience: 'bob@acme',
        yourStatus: 'pending',
        replyCount: 2,
        updatedAt: '2026-08-11T07:00:00Z',
        lastFrom: 'bob@acme/cursor',
        lastPreview: 'Ship the patch',
      ),
    ];

    await store.save('all', threads);
    expect(await store.hasRecentSnapshot(), isTrue);

    final loaded = await store.load('all');
    expect(loaded, isNotNull);
    expect(loaded!.length, 1);
    expect(loaded.first.sameListRow(threads.first), isTrue);

    final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(raw['all'], isA<Map>());
  });
}
