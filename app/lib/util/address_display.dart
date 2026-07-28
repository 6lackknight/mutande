/// Display formatting for mail addresses in the Mac UI.
///
/// Own agents use self shorthand (`@cursor`); never show `/default`.
String formatMailAddress(String address, {String? myHandle}) {
  var a = address.trim();
  if (a.isEmpty) return a;
  if (a.endsWith('/default')) {
    a = a.substring(0, a.length - '/default'.length);
  }
  // Already self shorthand (@claude) or org broadcast (@all@acme).
  if (a.startsWith('@')) return a;

  final mine = myHandle?.trim();
  if (mine == null || mine.isEmpty) return a;
  final myBare = mine.contains('/') ? mine.split('/').first : mine;
  if (myBare.isEmpty) return a;

  if (a == myBare) return a;
  if (a.startsWith('$myBare/')) {
    final slug = a.substring(myBare.length + 1);
    if (slug.isEmpty || slug == 'default') return myBare;
    return '@$slug';
  }
  return a;
}
