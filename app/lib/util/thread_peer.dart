/// Bare handle (`alice@acme`) from a display address (`alice@acme/claude`).
String bareMailHandle(String address) {
  final s = address.trim().toLowerCase();
  if (s.isEmpty) return '';
  final slash = s.indexOf('/');
  return slash >= 0 ? s.substring(0, slash) : s;
}

/// Other human on a 1:1 thread, or null for self-collab / broadcast / `@all`.
String? threadPeerHandle(
  String from,
  String audience, {
  String? myHandle,
}) {
  final fromBare = bareMailHandle(from);
  final audBare = bareMailHandle(audience);
  if (fromBare.isEmpty && audBare.isEmpty) return null;
  if (audBare.startsWith('@all')) return null;
  if (fromBare.isNotEmpty && fromBare == audBare) return null;

  final me = myHandle == null || myHandle.trim().isEmpty
      ? null
      : bareMailHandle(myHandle);
  if (me != null) {
    if (fromBare == me) return audBare.isEmpty ? null : audBare;
    if (audBare == me) return fromBare.isEmpty ? null : fromBare;
  }
  if (audBare.isNotEmpty) return audBare;
  return fromBare.isEmpty ? null : fromBare;
}

Map<String, String> avatarUrlsByHandle(Iterable<({String handle, String? avatarUrl})> contacts) {
  final out = <String, String>{};
  for (final c in contacts) {
    final url = c.avatarUrl?.trim();
    if (url == null || url.isEmpty) continue;
    final handle = bareMailHandle(c.handle);
    if (handle.isEmpty || handle.startsWith('@all')) continue;
    out[handle] = url;
  }
  return out;
}
