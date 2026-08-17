/// Semver helpers for desktop alpha update gating (major.minor.patch).
abstract final class VersionCompare {
  /// Normalizes `2.0.1+20` → `2.0.1`.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.split('+').first.trim();
  }

  /// Parses `major.minor.patch` (missing segments → 0). Returns null on bad input.
  static List<int>? parseParts(String? raw) {
    final normalized = normalize(raw);
    if (normalized == null) return null;
    final chunks = normalized.split('.');
    if (chunks.isEmpty || chunks.length > 4) return null;
    final parts = <int>[];
    for (final chunk in chunks) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty || !RegExp(r'^\d+$').hasMatch(trimmed)) return null;
      parts.add(int.parse(trimmed));
    }
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  /// Negative when [a] < [b], zero when equal, positive when [a] > [b].
  static int compare(String? a, String? b) {
    final pa = parseParts(a);
    final pb = parseParts(b);
    if (pa == null || pb == null) return 0;
    for (var i = 0; i < 3; i++) {
      final delta = pa[i] - pb[i];
      if (delta != 0) return delta;
    }
    return 0;
  }

  static bool isOlder(String current, String latest) =>
      compare(current, latest) < 0;
}
