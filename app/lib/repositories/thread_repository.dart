import '../services/daemon_client.dart';
import '../services/mailbox/mailbox_store.dart';

typedef MailboxGetter = MailboxStore? Function();

/// Local-first threads — UI reads mailbox; [ingestThread] decrypts via sidecar.
class ThreadRepository {
  ThreadRepository({
    required this.daemon,
    required this.mailbox,
    this.onMailboxChanged,
  });

  final DaemonClient daemon;
  final MailboxGetter mailbox;
  final void Function()? onMailboxChanged;

  void _tick() => onMailboxChanged?.call();

  Future<List<ThreadSummary>?> readList(String filter) async {
    return mailbox()?.loadThreadList(filter);
  }

  Future<ThreadDetailResult?> readDetail(String threadId) async {
    return mailbox()?.loadThreadDetail(threadId);
  }

  Future<bool> isDetailFresh(String threadId, String? listUpdatedAt) async {
    final box = mailbox();
    if (box == null) return false;
    return box.threadDetailIsFresh(threadId, listUpdatedAt);
  }

  /// Refresh list from hub and write mailbox. Returns the new list.
  Future<List<ThreadSummary>> refreshList({String? filter}) async {
    final key = filter ?? 'all';
    final rpcFilter =
        (key == 'all' || key == 'collab' || key == 'unfiled') ? null : key;
    final threads = await daemon.listThreads(filter: rpcFilter);
    final box = mailbox();
    if (box != null) {
      try {
        await box.saveThreadList(key, threads);
        _tick();
      } catch (_) {}
    }
    return threads;
  }

  /// Decrypt via sidecar and write-through mailbox (receive / miss path).
  Future<ThreadDetailResult> ingestThread(String threadId) async {
    final detail = await daemon.getThread(threadId);
    final box = mailbox();
    if (box != null) {
      try {
        await box.upsertThreadDetail(detail);
        _tick();
        return await box.loadThreadDetail(threadId) ?? detail;
      } catch (_) {}
    }
    return detail;
  }

  /// Ingest only when missing or fingerprint stale vs list row.
  Future<bool> ingestIfStale({
    required String threadId,
    String? listUpdatedAt,
  }) async {
    final box = mailbox();
    if (box != null) {
      final fresh = await box.threadDetailIsFresh(threadId, listUpdatedAt);
      if (fresh) return false;
    }
    await ingestThread(threadId);
    return true;
  }

  Future<void> deleteLocal(String threadId) async {
    final box = mailbox();
    if (box == null) return;
    await box.deleteThread(threadId);
    _tick();
  }
}
