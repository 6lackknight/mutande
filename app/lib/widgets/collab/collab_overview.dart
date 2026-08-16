import '../../services/daemon_client.dart';

/// Hub `laneBucket` — name first, then list position.
enum CollabLaneBucket { backlog, doing, done }

CollabLaneBucket collabLaneBucket(List<CollabListView> lists, String? laneId) {
  if (laneId == null || laneId.isEmpty) return CollabLaneBucket.backlog;
  CollabListView? list;
  for (final l in lists) {
    if (l.id == laneId) {
      list = l;
      break;
    }
  }
  if (list == null) return CollabLaneBucket.backlog;
  final name = list.name.trim().toLowerCase();
  if (name == 'doing') return CollabLaneBucket.doing;
  if (name == 'done') return CollabLaneBucket.done;
  if (name == 'backlog') return CollabLaneBucket.backlog;
  final sorted = [...lists]..sort((a, b) => a.position.compareTo(b.position));
  final idx = sorted.indexWhere((l) => l.id == laneId);
  if (idx <= 0) return CollabLaneBucket.backlog;
  if (idx == sorted.length - 1) return CollabLaneBucket.done;
  return CollabLaneBucket.doing;
}

/// Per-collab tallies derived from `getCollab` — no extra hub call.
class CollabOverview {
  const CollabOverview({
    this.open = 0,
    this.doing = 0,
    this.needsYou = 0,
    this.lastActivityAt,
  });

  final int open;
  final int doing;
  final int needsYou;
  final String? lastActivityAt;

  factory CollabOverview.fromDetail(CollabDetail collab) {
    var open = 0;
    var doing = 0;
    var needsYou = 0;
    String? last;

    for (final card in collab.cards) {
      final isOpen = card.status != 'closed';
      if (isOpen) {
        open += 1;
        if (collabLaneBucket(collab.lists, card.laneId) ==
            CollabLaneBucket.doing) {
          doing += 1;
        }
        if (card.needsYou) needsYou += 1;
      }
      final at = card.updatedAt?.trim();
      if (at != null && at.isNotEmpty) {
        final instant = DateTime.tryParse(at);
        final previous = last == null ? null : DateTime.tryParse(last);
        if (instant != null &&
            (previous == null || instant.isAfter(previous))) {
          last = at;
        }
      }
    }

    return CollabOverview(
      open: open,
      doing: doing,
      needsYou: needsYou,
      lastActivityAt: last,
    );
  }
}
