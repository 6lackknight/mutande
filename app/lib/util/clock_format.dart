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

/// Inbox time: `now` / `2m` / `3h` / today `HH:MM` / `yday` / `Aug 13`.
String formatRelativeTime(String? iso, {DateTime? now}) {
  if (iso == null || iso.trim().isEmpty) return '';
  final dt = DateTime.tryParse(iso.trim());
  if (dt == null) return '';
  final local = dt.toLocal();
  final n = now ?? DateTime.now();
  final diff = n.difference(local);
  if (diff.inSeconds.abs() < 45) return 'now';
  if (diff.inMinutes.abs() < 60) return '${diff.inMinutes.abs()}m';
  if (diff.inHours.abs() < 6) return '${diff.inHours.abs()}h';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return formatClockHm(iso);
  if (day == today.subtract(const Duration(days: 1))) return 'yday';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}';
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
