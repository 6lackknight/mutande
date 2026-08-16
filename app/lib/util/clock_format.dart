/// Local clock time `HH:MM` from an ISO-8601 timestamp (or empty if unparseable).
String formatClockHm(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '';
  final dt = DateTime.tryParse(iso.trim());
  if (dt == null) return '';
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Mail/collab age: last 24h local `HH:MM`, then `Nd` / `Nw` / `Nm` (months).
String formatRelativeTime(String? iso, {DateTime? now}) {
  if (iso == null || iso.trim().isEmpty) return '';
  final dt = DateTime.tryParse(iso.trim());
  if (dt == null) return '';
  final local = dt.toLocal();
  final n = now ?? DateTime.now();
  final age = n.difference(local);
  if (age.inHours < 24) return formatClockHm(iso);
  if (age.inDays < 7) return '${age.inDays}d';
  if (age.inDays < 30) return '${age.inDays ~/ 7}w';
  return '${age.inDays ~/ 30}m';
}

/// True when [iso] is within [window] of [now] (default 15 minutes).
bool isRecentActivity(
  String? iso, {
  DateTime? now,
  Duration window = const Duration(minutes: 15),
}) {
  if (iso == null || iso.trim().isEmpty) return false;
  final dt = DateTime.tryParse(iso.trim());
  if (dt == null) return false;
  return (now ?? DateTime.now()).difference(dt.toLocal()).abs() < window;
}
