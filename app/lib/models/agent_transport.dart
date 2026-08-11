/// Agent slot transport (hub-assigned). Wire values: `sidecar` | `mcp`.
enum AgentTransport {
  sidecar,
  mcp;

  /// Parse hub/daemon field; unknown or missing → null (legacy = hide chip).
  static AgentTransport? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    return switch (v) {
      'sidecar' => AgentTransport.sidecar,
      'mcp' || 'web' => AgentTransport.mcp,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
        AgentTransport.sidecar => 'sidecar',
        AgentTransport.mcp => 'mcp',
      };

  /// Quiet social-style chip label ("via iOS").
  String get chipLabel => switch (this) {
        AgentTransport.sidecar => 'via sidecar',
        AgentTransport.mcp => 'via web',
      };

  String get settingsLabel => switch (this) {
        AgentTransport.sidecar => 'Sidecar',
        AgentTransport.mcp => 'Web',
      };
}

/// Hub-assigned trust tier — drives non-E2E compose warnings.
enum TrustTier {
  org,
  external,
  enterprise;

  static TrustTier? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    return switch (v) {
      'org' => TrustTier.org,
      'external' => TrustTier.external,
      'enterprise' => TrustTier.enterprise,
      _ => null,
    };
  }

  String get wireValue => name;
}

/// Capability freshness TTL (§5.1 / §13) — UI only; never blocks routing.
const Duration kCapabilityFreshTtl = Duration(minutes: 15);

bool isCapabilityFresh(DateTime? lastSeen, {DateTime? now}) {
  if (lastSeen == null) return false;
  final t = now ?? DateTime.now();
  return !t.difference(lastSeen).isNegative &&
      t.difference(lastSeen) <= kCapabilityFreshTtl;
}

/// Compose-time non-E2E badge copy (§6.5.1).
class ComposeTransportWarning {
  const ComposeTransportWarning({
    required this.label,
    this.transport,
    this.trustTier,
  });

  /// e.g. `via web · not E2E`, `via external · not E2E`.
  final String label;
  final AgentTransport? transport;
  final TrustTier? trustTier;

  static ComposeTransportWarning? fromSlot({
    AgentTransport? transport,
    TrustTier? trustTier,
  }) {
    if (trustTier == TrustTier.enterprise) {
      return ComposeTransportWarning(
        label: 'via enterprise · not E2E',
        transport: transport,
        trustTier: trustTier,
      );
    }
    if (trustTier == TrustTier.external) {
      return ComposeTransportWarning(
        label: 'via external · not E2E',
        transport: transport,
        trustTier: trustTier,
      );
    }
    if (transport == AgentTransport.mcp) {
      return ComposeTransportWarning(
        label: 'via web · not E2E',
        transport: transport,
        trustTier: trustTier,
      );
    }
    return null;
  }
}

/// Slugs that have both sidecar and web rows.
List<String> dualTransportSlugs(
  Iterable<({String slug, AgentTransport? transport})> agents,
) {
  final bySlug = <String, Set<AgentTransport>>{};
  for (final a in agents) {
    final slug = a.slug.trim().toLowerCase();
    if (slug.isEmpty) continue;
    final t = a.transport;
    if (t == null) continue;
    bySlug.putIfAbsent(slug, () => {}).add(t);
  }
  final dual = <String>[];
  for (final e in bySlug.entries) {
    if (e.value.contains(AgentTransport.sidecar) &&
        e.value.contains(AgentTransport.mcp)) {
      dual.add(e.key);
    }
  }
  dual.sort();
  return dual;
}
