import 'package:flutter_test/flutter_test.dart';

import 'package:app/repositories/thread_repository.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/mailbox/mailbox_store.dart';

class _FakeDaemon extends Fake implements DaemonClient {
  _FakeDaemon({required this.threads, required this.details});

  final List<ThreadSummary> threads;
  final Map<String, ThreadDetailResult> details;
  int getThreadCalls = 0;

  @override
  Future<List<ThreadSummary>> listThreads({
    String? filter,
    bool? enrich,
  }) async =>
      threads;

  @override
  Future<ThreadDetailResult> getThread(String threadId) async {
    getThreadCalls++;
    final d = details[threadId];
    if (d == null) throw StateError('missing $threadId');
    return d;
  }
}

void main() {
  late MailboxStore store;

  setUp(() async {
    store = await MailboxStore.openMemory(userId: 'sync-user');
  });

  tearDown(() async {
    await store.close();
  });

  test('ingestIfStale decrypts once then skips when fingerprint matches', () async {
    const detail = ThreadDetailResult(
      id: 't1',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme',
      updatedAt: '2026-08-23T12:00:00Z',
      messages: [
        ThreadMessageView(
          id: 'm1',
          fromHandle: 'alice@acme',
          createdAt: '2026-08-23T12:00:00Z',
          bundleNotes: 'hi',
        ),
      ],
    );
    final daemon = _FakeDaemon(
      threads: const [
        ThreadSummary(
          id: 't1',
          kind: 'direct',
          status: 'open',
          from: 'alice@acme',
          audience: 'bob@acme',
          updatedAt: '2026-08-23T12:00:00Z',
        ),
      ],
      details: {'t1': detail},
    );
    final repo = ThreadRepository(
      daemon: daemon,
      mailbox: () => store,
    );

    expect(await repo.readDetail('t1'), isNull);
    expect(
      await repo.ingestIfStale(
        threadId: 't1',
        listUpdatedAt: '2026-08-23T12:00:00Z',
      ),
      isTrue,
    );
    expect(daemon.getThreadCalls, 1);
    expect(await repo.readDetail('t1'), isNotNull);

    expect(
      await repo.ingestIfStale(
        threadId: 't1',
        listUpdatedAt: '2026-08-23T12:00:00Z',
      ),
      isFalse,
    );
    expect(daemon.getThreadCalls, 1);
  });

  test('refreshList writes mailbox for DB-first open', () async {
    final daemon = _FakeDaemon(
      threads: const [
        ThreadSummary(
          id: 't2',
          kind: 'direct',
          status: 'open',
          from: 'alice@acme',
          audience: 'bob@acme',
          updatedAt: '2026-08-23T13:00:00Z',
          lastPreview: 'yo',
        ),
      ],
      details: const {},
    );
    final repo = ThreadRepository(daemon: daemon, mailbox: () => store);
    final list = await repo.refreshList();
    expect(list.single.id, 't2');
    final cached = await repo.readList('all');
    expect(cached?.single.lastPreview, 'yo');
  });
}
