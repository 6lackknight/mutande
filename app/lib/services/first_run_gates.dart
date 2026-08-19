import '../models/agent_transport.dart';
import 'daemon_client.dart';

/// Own registered agents that can send mail (never `/default`).
int firstRunOwnAgentCount(Iterable<AgentInfo> agents) {
  return agents
      .map((a) => a.slug.toLowerCase().trim())
      .where((s) => s.isNotEmpty && s != 'default')
      .toSet()
      .length;
}

/// A first handoff needs a recipient that is not the sending agent:
/// a second own host, or a teammate who already has a host.
bool firstRunDestinationReady({
  required int ownAgents,
  required bool liveTeammate,
}) => ownAgents >= 2 || (ownAgents >= 1 && liveTeammate);

const _ownHostOrder = ['cursor', 'claude', 'chatgpt'];

List<String> _ownHandoffSlugs({
  required Iterable<AgentInfo> ownAgents,
  String? sendingSlug,
}) {
  var sending = (sendingSlug ?? '').toLowerCase().trim();
  final all = ownAgents
      .map((a) => a.slug.toLowerCase().trim())
      .where((s) => s.isNotEmpty && s != 'default')
      .toSet();
  if (sending.isEmpty || !all.contains(sending)) {
    sending = _ownHostOrder.firstWhere(all.contains, orElse: () => '');
    if (sending.isEmpty) sending = all.firstOrNull ?? '';
  }
  final slugs = all.where((s) => s != sending).toList();
  slugs.sort((a, b) {
    final ai = _ownHostOrder.indexOf(a);
    final bi = _ownHostOrder.indexOf(b);
    if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
    if (ai >= 0) return -1;
    if (bi >= 0) return 1;
    return a.compareTo(b);
  });
  return slugs;
}

/// Destinations for the first handshake. Own hosts are `@slug` (one row even
/// when sidecar + web both exist). Teammates are bare handles.
List<String> firstRunHandoffChoices({
  required Iterable<AgentInfo> ownAgents,
  String? sendingSlug,
  Iterable<String> liveTeammateHandles = const [],
}) {
  final own = [
    for (final s in _ownHandoffSlugs(
      ownAgents: ownAgents,
      sendingSlug: sendingSlug,
    ))
      '@$s',
  ];
  final seen = {for (final t in own) t.toLowerCase()};
  final peers = <String>[];
  for (final raw in liveTeammateHandles) {
    final h = raw.trim().toLowerCase();
    if (h.isEmpty || seen.contains(h)) continue;
    seen.add(h);
    peers.add(h);
  }
  peers.sort();
  return [...own, ...peers];
}

/// Self-collab uses `@slug`; a teammate is their bare handle.
///
/// When a slug has both sidecar and hosted-MCP slots, `@chatgpt` still reaches
/// both — the picker is who, not which ChatGPT transport.
String? firstRunHandoffTarget({
  required Iterable<AgentInfo> ownAgents,
  String? sendingSlug,
  String? liveTeammateHandle,
  Iterable<String> liveTeammateHandles = const [],
}) {
  final peers = [
    ...liveTeammateHandles,
    if (liveTeammateHandle != null) liveTeammateHandle,
  ];
  final choices = firstRunHandoffChoices(
    ownAgents: ownAgents,
    sendingSlug: sendingSlug,
    liveTeammateHandles: peers,
  );
  return choices.firstOrNull;
}

String firstRunHandoffChoiceLabel(String target) {
  final slug = firstRunTargetHostSlug(target);
  return switch (slug) {
    'cursor' => 'Cursor',
    'claude' => 'Claude',
    'chatgpt' => 'ChatGPT',
    null => target.trim().toLowerCase(),
    final other => other,
  };
}

String? firstRunHandoffChoiceIconSlug(String target) =>
    firstRunTargetHostSlug(target);

/// Hub transport for [target] (`@chatgpt` → mcp when a web slot exists).
AgentTransport? firstRunHandoffTransport({
  required Iterable<AgentInfo> ownAgents,
  String? target,
}) {
  final slug = firstRunTargetHostSlug(target);
  if (slug == null) return null;
  final slots = ownAgents
      .where((a) => a.slug.toLowerCase().trim() == slug)
      .toList();
  if (slots.any((a) => a.transport == AgentTransport.mcp)) {
    return AgentTransport.mcp;
  }
  return slots.map((a) => a.transport).whereType<AgentTransport>().firstOrNull;
}

/// Sending-host transport: web only when that slug has no sidecar row.
AgentTransport? firstRunSendingTransport({
  required Iterable<AgentInfo> ownAgents,
  String? sendingSlug,
}) {
  final slug = (sendingSlug ?? '').toLowerCase().trim();
  if (slug.isEmpty || slug == 'default') return null;
  final slots = ownAgents
      .where((a) => a.slug.toLowerCase().trim() == slug)
      .toList();
  final hasMcp = slots.any((a) => a.transport == AgentTransport.mcp);
  final hasSidecar = slots.any((a) => a.transport == AgentTransport.sidecar);
  if (hasMcp && !hasSidecar) return AgentTransport.mcp;
  if (hasSidecar) return AgentTransport.sidecar;
  return slots.map((a) => a.transport).whereType<AgentTransport>().firstOrNull;
}

bool firstRunTargetIsTeammate(String target) {
  final t = target.trim();
  return t.isNotEmpty && !t.startsWith('@');
}

/// Agent slug inside `@chatgpt`. Null for a teammate handle.
String? firstRunTargetHostSlug(String? target) {
  final t = (target ?? '').trim().toLowerCase();
  if (!t.startsWith('@')) return null;
  final slug = t.substring(1).trim();
  if (slug.isEmpty || slug == 'default' || slug.contains('@')) return null;
  return slug;
}

/// Catalog id for opening a host (`chatgpt-web` vs `chatgpt`).
String firstRunComposerId({required String slug, AgentTransport? transport}) {
  final s = slug.toLowerCase().trim();
  if (transport == AgentTransport.mcp) {
    return switch (s) {
      'chatgpt' => 'chatgpt-web',
      'claude' => 'claude-web',
      _ => s,
    };
  }
  return s;
}

String firstRunHandshakePrompt(String target) {
  return 'Start a mutande thread with $target. '
      'If you haven’t introduced yourself on mutande yet, do that first. '
      'Ask them to reply with /handshake.';
}

/// Pasted into the receiving host so it answers the waiting thread.
String firstRunHandshakeReplyPrompt() {
  return 'There’s a mutande handshake waiting for you. '
      'Open the thread and reply with /handshake.';
}

bool firstRunSummaryMatchesTarget(ThreadSummary summary, String target) {
  final t = target.trim().toLowerCase();
  if (t.isEmpty) return false;
  if ((summary.collabId ?? '').trim().isNotEmpty) return false;
  final hay = [
    summary.audience,
    summary.from,
    summary.lastFrom ?? '',
  ].join(' ').toLowerCase();
  if (t.startsWith('@')) {
    final slug = t.substring(1);
    if (slug.isEmpty) return false;
    return hay.contains('/$slug');
  }
  return hay.contains(t);
}

bool _recentEnough(ThreadSummary summary, DateTime waitStarted) {
  final updated = DateTime.tryParse(summary.updatedAt ?? '');
  if (updated == null) return true;
  return !updated.isBefore(waitStarted.subtract(const Duration(minutes: 5)));
}

/// Thread the sending agent just opened — show it before any reply.
bool isFirstRunOutboundCandidate({
  required ThreadSummary summary,
  required DateTime waitStarted,
  required String target,
}) {
  if (!firstRunSummaryMatchesTarget(summary, target)) return false;
  return _recentEnough(summary, waitStarted);
}

/// Whether [summary] is worth opening while watching for the first reply.
///
/// Skip decrypt until hub metadata shows a reply, and skip threads that have
/// not moved since shortly before the wait started.
bool isFirstRunHandoffCandidate({
  required ThreadSummary summary,
  required DateTime waitStarted,
  required String target,
}) {
  if (summary.replyCount < 1) return false;
  return isFirstRunOutboundCandidate(
    summary: summary,
    waitStarted: waitStarted,
    target: target,
  );
}

bool _isPingRoot(ThreadMessageView root) {
  final ping = root.pingKind?.trim().toLowerCase();
  return ping != null && ping.isNotEmpty;
}

ThreadMessageView firstRunThreadRoot(ThreadDetailResult detail) {
  final roots = detail.messages
      .where((m) => m.parentMessageId == null && m.inReplyTo == null)
      .toList();
  return roots.isNotEmpty ? roots.first : detail.messages.first;
}

/// True when a non-ping thread has a handshake reply from someone other than
/// the sender.
bool isFirstRunHandshakeReply(ThreadDetailResult detail) {
  if (detail.messages.isEmpty) return false;
  final root = firstRunThreadRoot(detail);
  if (_isPingRoot(root)) return false;
  final from = root.fromHandle.trim().toLowerCase();
  return detail.messages.any((m) {
    if (m.id == root.id) return false;
    if (m.fromHandle.trim().toLowerCase() == from) return false;
    return m.hasHandshake;
  });
}
