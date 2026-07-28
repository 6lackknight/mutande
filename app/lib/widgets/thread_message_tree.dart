import '../services/daemon_client.dart';

/// A message positioned in a nested thread tree (depth 0 = top-level).
class ThreadMessageNode {
  const ThreadMessageNode({required this.message, required this.depth});

  final ThreadMessageView message;
  final int depth;
}

/// Flatten messages into Reddit-style order: parent, then nested replies.
List<ThreadMessageNode> flattenThreadMessages(List<ThreadMessageView> messages) {
  if (messages.isEmpty) return const [];

  final byId = {for (final m in messages) m.id: m};
  final children = <String, List<ThreadMessageView>>{};
  final roots = <ThreadMessageView>[];

  int compareCreated(ThreadMessageView a, ThreadMessageView b) =>
      a.createdAt.compareTo(b.createdAt);

  for (final m in messages) {
    final parent = m.replyParentId;
    if (parent == null || parent.isEmpty || !byId.containsKey(parent)) {
      roots.add(m);
    } else {
      children.putIfAbsent(parent, () => []).add(m);
    }
  }

  roots.sort(compareCreated);
  for (final list in children.values) {
    list.sort(compareCreated);
  }

  final out = <ThreadMessageNode>[];
  void walk(ThreadMessageView m, int depth) {
    out.add(ThreadMessageNode(message: m, depth: depth));
    for (final child in children[m.id] ?? const []) {
      walk(child, depth + 1);
    }
  }

  for (final root in roots) {
    walk(root, 0);
  }
  return out;
}
