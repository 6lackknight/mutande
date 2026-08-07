/// Display formatting for mail addresses in the Mac UI.
///
/// Own agents use self shorthand (`@cursor`); never show `/default`.
/// Addresses are shown lowercase (`alice@acme/cursor`, not `Alice@…/Cursor`).
String formatMailAddress(String address, {String? myHandle}) {
  var a = address.trim();
  if (a.isEmpty) return a;

  // Strip /default case-insensitively before canonicalizing.
  final lowerA = a.toLowerCase();
  if (lowerA.endsWith('/default')) {
    a = a.substring(0, a.length - '/default'.length);
  }

  final mine = myHandle?.trim();
  if (mine != null && mine.isNotEmpty) {
    final myBare = (mine.contains('/') ? mine.split('/').first : mine)
        .toLowerCase();
    if (myBare.isNotEmpty) {
      final aLower = a.toLowerCase();
      if (aLower == myBare) {
        return myBare;
      }
      if (aLower.startsWith('$myBare/')) {
        final slug = aLower.substring(myBare.length + 1);
        if (slug.isEmpty || slug == 'default') return myBare;
        return '@$slug';
      }
    }
  }

  // Already self shorthand (@claude) or org broadcast (@all@acme) — lowercase.
  return a.toLowerCase();
}
