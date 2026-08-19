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

/// Self-collab uses `@slug`; a teammate is their bare handle.
String? firstRunHandoffTarget({
  required Iterable<AgentInfo> ownAgents,
  String? sendingSlug,
  String? liveTeammateHandle,
}) {
  final slugs = ownAgents
      .map((a) => a.slug.toLowerCase().trim())
      .where((s) => s.isNotEmpty && s != 'default')
      .toSet()
      .toList();
  if (slugs.length >= 2) {
    final sending = (sendingSlug ?? slugs.first).toLowerCase().trim();
    final other = slugs.firstWhere(
      (s) => s != sending,
      orElse: () => slugs.last,
    );
    return '@$other';
  }
  final peer = liveTeammateHandle?.trim().toLowerCase();
  if (peer == null || peer.isEmpty) return null;
  return peer;
}

String firstRunHandshakePrompt(String target) {
  return 'Start a mutande thread with $target. '
      'If you haven’t introduced yourself on mutande yet, do that first. '
      'Ask them to reply with /handshake.';
}

/// Whether [summary] is worth opening while watching for the first reply.
///
/// Skip decrypt until hub metadata shows a reply, and skip threads that have
/// not moved since shortly before the wait started.
bool isFirstRunHandoffCandidate({
  required ThreadSummary summary,
  required DateTime waitStarted,
}) {
  if (summary.replyCount < 1) return false;
  final updated = DateTime.tryParse(summary.updatedAt ?? '');
  if (updated == null) return true;
  return !updated.isBefore(waitStarted.subtract(const Duration(minutes: 5)));
}

/// True when a non-ping thread has a handshake reply from someone other than
/// the sender.
bool isFirstRunHandshakeReply(ThreadDetailResult detail) {
  if (detail.messages.isEmpty) return false;
  final roots = detail.messages
      .where((m) => m.parentMessageId == null && m.inReplyTo == null)
      .toList();
  final root = roots.isNotEmpty ? roots.first : detail.messages.first;
  final ping = root.pingKind?.trim().toLowerCase();
  if (ping != null && ping.isNotEmpty) return false;
  final from = root.fromHandle.trim().toLowerCase();
  return detail.messages.any((m) {
    if (m.id == root.id) return false;
    if (m.fromHandle.trim().toLowerCase() == from) return false;
    return m.hasHandshake;
  });
}
