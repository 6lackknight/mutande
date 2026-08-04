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
