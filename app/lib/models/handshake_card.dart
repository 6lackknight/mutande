/// Typed intro from `bundle.handshake` (or the notes dump agents still mail).
class HandshakeCardView {
  const HandshakeCardView({
    this.host,
    this.address,
    this.models = const [],
    this.skills = const [],
    this.askMeAbout = const [],
    this.preferredFileFormat,
    this.otherTools = const [],
  });

  factory HandshakeCardView.fromJson(Map<String, dynamic> map) {
    return HandshakeCardView(
      host: _one(map['host']),
      address: _one(map['address']),
      models: _list(map['models']),
      skills: _list(map['skills']),
      askMeAbout: _list(map['ask_me_about']),
      preferredFileFormat: _one(map['preferred_file_format']),
      otherTools: _list(map['other_tools']),
    );
  }

  /// Labeled dump from [handshake_notes] / hosted MCP. Null when notes are prose.
  static HandshakeCardView? tryParseNotes(String? notes) {
    final raw = notes?.trim();
    if (raw == null || raw.isEmpty) return null;
    String? host;
    String? address;
    var models = const <String>[];
    var skills = const <String>[];
    var ask = const <String>[];
    String? files;
    var tools = const <String>[];
    var labeled = 0;
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.toLowerCase() == 'handshake') continue;
      final colon = t.indexOf(':');
      if (colon <= 0) return null;
      final key = t.substring(0, colon).trim().toLowerCase();
      final value = t.substring(colon + 1).trim();
      if (value.isEmpty) continue;
      labeled++;
      switch (key) {
        case 'host':
          host = value;
        case 'address':
          address = value;
        case 'models':
          models = _split(value);
        case 'skills':
          skills = _split(value);
        case 'ask me about':
          ask = _split(value);
        case 'preferred files':
        case 'preferred file format':
          files = value;
        case 'other tools':
          tools = _split(value);
        default:
          return null;
      }
    }
    if (labeled == 0) return null;
    return HandshakeCardView(
      host: host,
      address: address,
      models: models,
      skills: skills,
      askMeAbout: ask,
      preferredFileFormat: files,
      otherTools: tools,
    );
  }

  final String? host;
  final String? address;
  final List<String> models;
  final List<String> skills;
  final List<String> askMeAbout;
  final String? preferredFileFormat;
  final List<String> otherTools;

  /// Typed card, or the labeled dump in [notes]. Null for ordinary mail.
  static HandshakeCardView? resolve({
    HandshakeCardView? handshake,
    String? notes,
  }) {
    final card = handshake ?? tryParseNotes(notes);
    if (card == null || card.isEmpty) return null;
    return card;
  }

  /// True when [notes] are the labeled dump rather than a written intro.
  static bool notesAreDump(String? notes) => tryParseNotes(notes) != null;

  bool get isEmpty =>
      (host == null || host!.isEmpty) &&
      (address == null || address!.isEmpty) &&
      models.isEmpty &&
      skills.isEmpty &&
      askMeAbout.isEmpty &&
      (preferredFileFormat == null || preferredFileFormat!.isEmpty) &&
      otherTools.isEmpty;

  /// Collapsed-mail snippet — the human lead, not the dump.
  String get blurb {
    if (askMeAbout.isNotEmpty) return leadSentence;
    if (skills.isNotEmpty) return skills.join(', ');
    return host?.trim() ?? '';
  }

  /// Body copy when the mailed notes are only the labeled dump.
  String get leadSentence {
    if (askMeAbout.isEmpty) return '';
    if (askMeAbout.length == 1) return 'Ask me about ${askMeAbout.first}.';
    if (askMeAbout.length == 2) {
      return 'Ask me about ${askMeAbout[0]} and ${askMeAbout[1]}.';
    }
    final last = askMeAbout.last;
    final rest = askMeAbout.sublist(0, askMeAbout.length - 1).join(', ');
    return 'Ask me about $rest, and $last.';
  }

  /// Quiet extras under the body — no field labels.
  String get extrasLine {
    final bits = <String>[
      ...skills,
      ...models,
      ...otherTools,
      if ((preferredFileFormat ?? '').trim().isNotEmpty)
        preferredFileFormat!.trim(),
    ];
    return bits.join(' · ');
  }

  static String? _one(Object? value) {
    if (value is String) {
      final t = value.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  static List<String> _list(Object? value) {
    if (value is List) {
      return [
        for (final e in value)
          if (e is String && e.trim().isNotEmpty) e.trim(),
      ];
    }
    if (value is String) return _split(value);
    return const [];
  }

  static List<String> _split(String value) {
    return [
      for (final p in value.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
  }
}
