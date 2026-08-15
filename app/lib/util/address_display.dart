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

/// Local-part of `alice@acme` → `alice`.
String handleLocalPart(String handle) {
  final h = formatMailAddress(handle);
  final at = h.indexOf('@');
  if (at <= 0) return h;
  return h.substring(0, at);
}

/// Full name from hub `display_name`. If missing, title-case the handle local-part
/// (`tawanda@tbhco` → `Tawanda`) — not an invented surname.
String personDisplayTitle({String? displayName, required String handle}) {
  final n = displayName?.trim();
  if (n != null && n.isNotEmpty) return n;
  return titleCaseLocalPart(handle);
}

/// `tawanda` → `Tawanda`; `tawanda.brandon` → `Tawanda Brandon`.
String titleCaseLocalPart(String handle) {
  final local = handleLocalPart(handle);
  if (local.isEmpty) return local;
  return local.split(RegExp(r'[._-]+')).where((p) => p.isNotEmpty).map((p) {
    return p[0].toUpperCase() + p.substring(1).toLowerCase();
  }).join(' ');
}

/// Initials from a display name (`Tawanda Brandon` → `TB`) or local-part (`tawanda` → `TA`).
String personInitials(String title) {
  final parts = title
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  String letter(String w) {
    for (final r in w.runes) {
      final ch = String.fromCharCode(r);
      if (RegExp(r'[A-Za-z0-9]').hasMatch(ch)) return ch.toUpperCase();
    }
    return '';
  }

  if (parts.length >= 2) {
    final a = letter(parts[0]);
    final b = letter(parts[1]);
    if (a.isNotEmpty && b.isNotEmpty) return '$a$b';
    if (a.isNotEmpty) return a;
  }
  final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (cleaned.isEmpty) return '?';
  if (cleaned.length == 1) return cleaned.toUpperCase();
  return cleaned.substring(0, 2).toUpperCase();
}
