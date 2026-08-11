import '../models/agent_transport.dart';
import '../services/daemon_client.dart';
import '../services/transport_prefs_store.dart';

/// Resolve compose non-E2E badge for [recipient] from known agent slots.
///
/// Returns null when transport is unknown (pre-L1) or target is sidecar E2E.
ComposeTransportWarning? resolveComposeTransportWarning({
  required String recipient,
  required List<AgentInfo> agents,
  TransportPrefs prefs = const TransportPrefs(),
}) {
  // Prefer exact agent_id / address match with enterprise trust_tier.
  final exact = _matchByAddressOrSlug(recipient, agents, prefs);
  if (exact != null) {
    return ComposeTransportWarning.fromSlot(
      transport: exact.transport,
      trustTier: exact.trustTier,
    );
  }
  return null;
}

/// Bare enterprise registry address candidate (`assistant@openai`).
///
/// Excludes self shorthand (`@claude`), broadcasts (`@all`, `@all@org`),
/// and agent-scoped handles (`bob@acme/claude`) — those resolve via agents.
String? registryAddressCandidate(String recipient) {
  final trimmed = recipient.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('@')) return null;
  if (trimmed.contains('/')) return null;
  final at = trimmed.indexOf('@');
  if (at <= 0 || at >= trimmed.length - 1) return null;
  return trimmed;
}

AgentInfo? _matchByAddressOrSlug(
  String recipient,
  List<AgentInfo> agents,
  TransportPrefs prefs,
) {
  final slug = _extractAgentSlug(recipient);
  if (slug == null) return null;

  final matches = agents
      .where((a) => a.slug.trim().toLowerCase() == slug)
      .toList(growable: false);
  if (matches.isEmpty) return null;

  if (matches.length == 1) return matches.first;

  final preferred = prefs.defaultFor(slug) ?? AgentTransport.sidecar;
  return matches.cast<AgentInfo?>().firstWhere(
        (a) => a!.transport == preferred,
        orElse: () => matches.first,
      );
}

String? _extractAgentSlug(String recipient) {
  final trimmed = recipient.trim().toLowerCase();
  if (trimmed.isEmpty) return null;

  // Self shorthand: @claude / @chatgpt (not @all, not @all@org).
  if (trimmed.startsWith('@') && !trimmed.substring(1).contains('@')) {
    final slug = trimmed.substring(1);
    if (slug.isEmpty || slug == 'all') return null;
    return slug;
  }

  // handle/slug
  final slash = trimmed.lastIndexOf('/');
  if (slash > 0 && slash < trimmed.length - 1) {
    final slug = trimmed.substring(slash + 1);
    if (slug.isEmpty || slug == 'default' || slug == 'all') return null;
    return slug;
  }

  return null;
}
