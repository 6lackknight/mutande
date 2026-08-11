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
  final slug = _extractAgentSlug(recipient);
  if (slug == null) return null;

  final matches = agents
      .where((a) => a.slug.trim().toLowerCase() == slug)
      .toList(growable: false);
  if (matches.isEmpty) return null;

  AgentInfo? chosen;
  if (matches.length == 1) {
    chosen = matches.first;
  } else {
    final preferred = prefs.defaultFor(slug) ?? AgentTransport.sidecar;
    chosen = matches.cast<AgentInfo?>().firstWhere(
          (a) => a!.transport == preferred,
          orElse: () => matches.first,
        );
  }

  return ComposeTransportWarning.fromSlot(
    transport: chosen?.transport,
    trustTier: chosen?.trustTier,
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
