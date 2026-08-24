import '../services/daemon_client.dart';
import 'thread_repository.dart';

/// Local-first collabs — decrypt via sidecar on ingest, not on UI open.
class CollabRepository {
  CollabRepository({
    required this.daemon,
    required this.mailbox,
    this.onMailboxChanged,
  });

  final DaemonClient daemon;
  final MailboxGetter mailbox;
  final void Function()? onMailboxChanged;

  void _tick() => onMailboxChanged?.call();

  Future<({List<CollabSummary> collabs, CollabPortfolio portfolio})?>
  readList({bool archived = false}) async {
    return mailbox()?.loadCollabList(archived: archived);
  }

  Future<CollabDetail?> readDetail(String collabId) async {
    return mailbox()?.loadCollabDetail(collabId);
  }

  Future<({List<CollabSummary> collabs, CollabPortfolio portfolio})>
  refreshList({bool archived = false}) async {
    final listed = await daemon.listCollabs(archived: archived);
    final box = mailbox();
    if (box != null) {
      try {
        await box.saveCollabList(
          collabs: listed.collabs,
          portfolio: listed.portfolio,
          archived: archived,
        );
        _tick();
      } catch (_) {}
    }
    return (collabs: listed.collabs, portfolio: listed.portfolio);
  }

  Future<CollabDetail> ingestCollab(
    String collabId, {
    String? listFingerprint,
  }) async {
    final detail = await daemon.getCollab(collabId);
    final box = mailbox();
    if (box != null) {
      try {
        await box.upsertCollabDetail(
          detail,
          listFingerprint: listFingerprint,
        );
        _tick();
        return await box.loadCollabDetail(collabId) ?? detail;
      } catch (_) {}
    }
    return detail;
  }

  Future<bool> ingestIfStale({
    required String collabId,
    String? listUpdatedAt,
  }) async {
    final box = mailbox();
    if (box != null) {
      final fresh = await box.collabDetailIsFresh(collabId, listUpdatedAt);
      if (fresh) return false;
    }
    await ingestCollab(collabId, listFingerprint: listUpdatedAt);
    return true;
  }
}
