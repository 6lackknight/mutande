import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/agent_transport.dart';
import '../services/daemon_client.dart';
import '../services/transport_prefs_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/compose_transport.dart';
import 'create_collab_sheet.dart' show CollabPendingFile, collabFileSizeLabel;
import 'enterprise_warn_banner.dart';
import 'mutande_stagger.dart';
import 'pane_quiet_state.dart';
import 'thinking_orb.dart';
import 'transport_chip.dart';

enum ComposeDispatchPhase { pick, write }

/// Hint line for an address row in the dispatch picker.
String composeAddressHint(String address) {
  final a = address.trim().toLowerCase();
  if (a.isEmpty) return '';
  if (a == '@all') return 'your agents';
  if (a.startsWith('@all@')) return 'broadcast';
  if (a.startsWith('@') && !a.substring(1).contains('@')) {
    return a.substring(1);
  }
  final slash = a.lastIndexOf('/');
  if (slash > 0 && slash < a.length - 1) {
    return a.substring(slash + 1);
  }
  return 'teammate';
}

/// Spotlight compose — address first, note after a pick. Pops `true` on send.
Future<bool> showComposeDispatch({
  required BuildContext context,
  required DaemonClient daemon,
  String? myHandle,
  String? initialRecipient,
}) async {
  final reduce = MediaQuery.disableAnimationsOf(context);
  final sent = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Dispatch',
    barrierColor: const Color(0x400C0A09),
    transitionDuration: reduce ? Duration.zero : MutandeMotion.ui,
    pageBuilder: (ctx, animation, secondary) {
      return ComposeDispatchSheet(
        daemon: daemon,
        myHandle: myHandle,
        initialRecipient: initialRecipient,
      );
    },
    transitionBuilder: (ctx, animation, secondary, child) {
      if (reduce) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: MutandeMotion.easeOut,
        reverseCurve: MutandeMotion.easeOut,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: const Alignment(0, -0.45),
          child: child,
        ),
      );
    },
  );
  return sent == true;
}

class ComposeDispatchSheet extends StatefulWidget {
  const ComposeDispatchSheet({
    super.key,
    required this.daemon,
    this.myHandle,
    this.initialRecipient,
    this.pickFiles,
  });

  final DaemonClient daemon;
  final String? myHandle;
  final String? initialRecipient;
  final Future<List<CollabPendingFile>> Function()? pickFiles;

  @override
  State<ComposeDispatchSheet> createState() => _ComposeDispatchSheetState();
}

class _ComposeDispatchSheetState extends State<ComposeDispatchSheet> {
  final _query = TextEditingController();
  final _subject = TextEditingController();
  final _notes = TextEditingController();
  final _queryFocus = FocusNode();
  final _subjectFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _files = <CollabPendingFile>[];

  ComposeDispatchPhase _phase = ComposeDispatchPhase.pick;
  final _recipients = <String>[];
  List<String> _options = const [];
  bool _sending = false;
  String? _error;
  ComposeTransportWarning? _transportWarning;
  bool _enterpriseWarn = false;
  List<AgentInfo> _agents = const [];
  TransportPrefs _transportPrefs = const TransportPrefs();
  Timer? _optionsDebounce;
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialRecipient?.trim() ?? '';
    if (seed.isNotEmpty) {
      _recipients.add(seed.toLowerCase());
      _phase = ComposeDispatchPhase.write;
    }
    _query.addListener(_onQueryTyped);
    _queryFocus.addListener(_onQueryFocus);
    _subject.addListener(_onBodyTyped);
    _notes.addListener(_onBodyTyped);
    unawaited(_loadTransportContext());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_phase == ComposeDispatchPhase.write) {
        _subjectFocus.requestFocus();
      } else {
        _queryFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _optionsDebounce?.cancel();
    _query.removeListener(_onQueryTyped);
    _queryFocus.removeListener(_onQueryFocus);
    _subject.removeListener(_onBodyTyped);
    _notes.removeListener(_onBodyTyped);
    _query.dispose();
    _subject.dispose();
    _notes.dispose();
    _queryFocus.dispose();
    _subjectFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _onQueryTyped() {
    setState(() {});
    _optionsDebounce?.cancel();
    _optionsDebounce = Timer(const Duration(milliseconds: 80), () {
      if (mounted) unawaited(_refreshOptions());
    });
  }

  void _onBodyTyped() => setState(() {});

  void _onQueryFocus() => setState(() {});

  Future<void> _loadTransportContext() async {
    TransportPrefs prefs = const TransportPrefs();
    List<AgentInfo> agents = const [];
    try {
      try {
        prefs = TransportPrefs.fromJson(
          await widget.daemon.getTransportDefaults(),
        );
      } catch (_) {
        prefs = await TransportPrefsStore().load();
      }
    } catch (_) {}
    try {
      agents = (await widget.daemon.listAgents()).agents;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _transportPrefs = prefs;
      _agents = agents;
    });
    unawaited(_refreshOptions());
    if (_recipients.isNotEmpty) unawaited(_resolveWarnings());
  }

  List<String> get _visibleOptions {
    final taken = {for (final r in _recipients) r.toLowerCase()};
    return [
      for (final o in _options)
        if (!taken.contains(o.toLowerCase())) o,
    ];
  }

  bool get _showAddSuggestions =>
      _phase == ComposeDispatchPhase.write &&
      (_queryFocus.hasFocus || _query.text.trim().isNotEmpty);

  Future<void> _refreshOptions() async {
    final next = await _recipientOptions(_query.text);
    if (!mounted) return;
    setState(() => _options = next);
  }

  Future<void> _resolveWarnings() async {
    final gen = ++_resolveGeneration;
    ComposeTransportWarning? warning;
    var enterpriseWarn = false;
    for (final recipient in _recipients) {
      var next = resolveComposeTransportWarning(
        recipient: recipient,
        agents: _agents,
        prefs: _transportPrefs,
      );
      warning ??= next;
      var enterprise = next?.isEnterprise ?? false;
      if (!enterprise) {
        final candidate = registryAddressCandidate(recipient);
        if (candidate != null) {
          final listing = await widget.daemon.getRegistryListing(candidate);
          if (!mounted || gen != _resolveGeneration) return;
          if (listing != null && listing.showBanner) {
            enterprise = true;
            next ??= ComposeTransportWarning.fromSlot(
              transport: AgentTransport.mcp,
              trustTier: TrustTier.enterprise,
            );
            warning ??= next;
          }
        }
      }
      if (enterprise) enterpriseWarn = true;
    }

    if (!mounted || gen != _resolveGeneration) return;
    if (warning?.label == _transportWarning?.label &&
        enterpriseWarn == _enterpriseWarn) {
      return;
    }
    setState(() {
      _transportWarning = warning;
      _enterpriseWarn = enterpriseWarn;
    });
  }

  Future<List<String>> _recipientOptions(String input) async {
    final trimmed = input.trim();
    final lower = trimmed.toLowerCase();
    final orgAll = orgBroadcastFromHandle(widget.myHandle);

    final selfShorthand =
        trimmed.isEmpty ||
        (trimmed.startsWith('@') && !trimmed.substring(1).contains('@'));
    if (selfShorthand) {
      try {
        final list = await widget.daemon.listAgents();
        final suggestions = <String>[
          '@all',
          if (orgAll != null) orgAll,
          ...list.agents.map((a) => '@${a.slug.toLowerCase()}'),
        ];
        if (trimmed.isEmpty || lower == '@') return suggestions;
        return suggestions.where((s) => s.startsWith(lower)).toList();
      } catch (_) {
        if (trimmed.isEmpty || lower.startsWith('@')) {
          return ['@all', if (orgAll != null) orgAll];
        }
      }
    }

    if (orgAll != null &&
        (orgAll.startsWith(lower) || lower.startsWith('@all@'))) {
      return [orgAll];
    }

    final bare = bareHandleFromInput(trimmed);
    if (bare == null) return const [];
    try {
      final list = await widget.daemon.listAgents(handle: bare);
      return [bare, ...list.agents.map((a) => '$bare/${a.slug.toLowerCase()}')];
    } catch (_) {
      return [bare];
    }
  }

  void _pick(String label) {
    final next = label.trim().toLowerCase();
    if (next.isEmpty || _recipients.contains(next)) {
      if (_recipients.contains(next)) _query.clear();
      return;
    }
    final first = _recipients.isEmpty;
    setState(() {
      _recipients.add(next);
      _query.clear();
      _phase = ComposeDispatchPhase.write;
      _error = null;
    });
    unawaited(_resolveWarnings());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (first) {
        _subjectFocus.requestFocus();
      } else {
        _queryFocus.requestFocus();
      }
    });
  }

  void _submitQuery() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    final lower = q.toLowerCase();
    final options = _visibleOptions;
    for (final m in options) {
      if (m.toLowerCase() == lower) {
        _pick(m);
        return;
      }
    }
    if (options.length == 1) {
      _pick(options.first);
      return;
    }
    if (q.startsWith('@') || q.contains('@')) {
      _pick(q);
    }
  }

  void _removeRecipient(String address) {
    setState(() {
      _recipients.remove(address);
      if (_recipients.isEmpty) {
        _phase = ComposeDispatchPhase.pick;
        _transportWarning = null;
        _enterpriseWarn = false;
      }
    });
    unawaited(_refreshOptions());
    if (_recipients.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _queryFocus.requestFocus();
      });
    } else {
      unawaited(_resolveWarnings());
    }
  }

  bool get _canSend =>
      _recipients.isNotEmpty &&
      !_sending &&
      (_notes.text.trim().isNotEmpty ||
          _subject.text.trim().isNotEmpty ||
          _files.isNotEmpty);

  Future<void> _attachFiles() async {
    if (_sending) return;
    try {
      final picked = widget.pickFiles != null
          ? await widget.pickFiles!()
          : await _pickFiles();
      if (!mounted || picked.isEmpty) return;
      setState(() {
        for (final f in picked) {
          if (f.path.trim().isEmpty) continue;
          if (_files.any((e) => e.path == f.path)) continue;
          _files.add(f);
        }
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not attach that file.');
    }
  }

  Future<List<CollabPendingFile>> _pickFiles() async {
    final files = await openFiles(confirmButtonText: 'Attach');
    final out = <CollabPendingFile>[];
    for (final f in files) {
      if (f.path.trim().isEmpty) continue;
      int? size;
      try {
        size = await f.length();
      } catch (_) {}
      out.add(
        CollabPendingFile(
          name: f.name,
          path: f.path,
          mime: f.mimeType,
          size: size,
        ),
      );
    }
    return out;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final notes = _notes.text.trim();
    final subject = _subject.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      for (final recipient in List<String>.from(_recipients)) {
        String? threadId;
        if (notes.isNotEmpty || subject.isNotEmpty) {
          threadId = await widget.daemon.forwardDraft(
            recipient: recipient,
            notes: notes,
            subject: subject.isEmpty ? null : subject,
          );
        }
        for (final file in _files) {
          threadId = await widget.daemon.forwardBlob(
            recipient: threadId == null ? recipient : null,
            threadId: threadId,
            path: file.path,
            subject: subject.isEmpty ? null : subject,
          );
        }
      }
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyDaemonError(e, what: 'Send');
        _sending = false;
      });
    }
  }

  void _close() {
    if (_sending) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Align(
        alignment: const Alignment(0, -0.45),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 512,
              maxHeight: (size.height * 0.72).clamp(280.0, 560.0),
            ),
            child: Material(
              key: const Key('compose-dispatch'),
              color: Colors.transparent,
              elevation: 0,
              shadowColor: const Color(0x80292524),
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment(-0.9, -1),
                    end: Alignment(0.85, 1),
                    colors: [
                      Color(0xFFE9E6E0),
                      Color(0xFFD2CDC5),
                      Color(0xFFBDB6AD),
                    ],
                    stops: [0.0, 0.46, 1.0],
                  ),
                  border: Border.all(color: const Color(0xFF8E877E)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66292524),
                      blurRadius: 40,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 36,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Dispatch',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: MutandeColors.stone600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: MutandeMotion.of(
                                context,
                                MutandeMotion.ui,
                              ),
                              switchInCurve: MutandeMotion.easeOut,
                              switchOutCurve: MutandeMotion.easeOut,
                              child: _phase == ComposeDispatchPhase.pick
                                  ? KeyedSubtree(
                                      key: const ValueKey('pick'),
                                      child: _pickPhase(),
                                    )
                                  : KeyedSubtree(
                                      key: const ValueKey('write'),
                                      child: _writePhase(),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickPhase() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('compose-who-field'),
          controller: _query,
          focusNode: _queryFocus,
          enabled: !_sending,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitQuery(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: MutandeColors.stone800,
          ),
          cursorColor: MutandeColors.stone800,
          decoration: const InputDecoration(
            hintText: 'Who should get this?',
            hintStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.3,
              color: MutandeColors.stone400,
            ),
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.only(bottom: 10),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
        const Divider(height: 1, color: Color(0x668E877E)),
        const SizedBox(height: 8),
        Flexible(
          child: MutandeStaggerScope(
            delay: MutandeStaggerScope.stagger,
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _visibleOptions.length,
              itemBuilder: (context, i) {
                final address = _visibleOptions[i];
                return MutandeStaggerIn(
                  id: address,
                  child: _AddressRow(
                    address: address,
                    onTap: _sending ? null : () => _pick(address),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _writePhase() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'To',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: MutandeColors.stone600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                key: const Key('compose-to-chip'),
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final r in _recipients)
                    GestureDetector(
                      onTap: _sending ? null : () => _removeRecipient(r),
                      child: Container(
                        key: Key('compose-to-chip-$r'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: MutandeColors.stone800,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          r,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: MutandeColors.stone50,
                          ),
                        ),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 72,
                      maxWidth: 168,
                    ),
                    child: TextField(
                      key: const Key('compose-who-field'),
                      controller: _query,
                      focusNode: _queryFocus,
                      enabled: !_sending,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitQuery(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: MutandeColors.stone800,
                      ),
                      cursorColor: MutandeColors.stone800,
                      decoration: const InputDecoration(
                        hintText: 'Add',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: MutandeColors.stone500,
                        ),
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_showAddSuggestions && _visibleOptions.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _visibleOptions.length,
              itemBuilder: (context, i) {
                final address = _visibleOptions[i];
                return _AddressRow(
                  address: address,
                  onTap: _sending ? null : () => _pick(address),
                );
              },
            ),
          ),
        ],
        if (_transportWarning != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ComposeNonE2eChip(warning: _transportWarning!),
          ),
        ],
        if (_enterpriseWarn) ...[
          const SizedBox(height: 8),
          const EnterpriseWarnBanner(),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('compose-subject-field'),
          controller: _subject,
          focusNode: _subjectFocus,
          enabled: !_sending,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _noteFocus.requestFocus(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: MutandeColors.stone800,
          ),
          cursorColor: MutandeColors.stone800,
          decoration: const InputDecoration(
            hintText: 'Subject',
            hintStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
              color: MutandeColors.stone400,
            ),
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.only(bottom: 8),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
        const Divider(height: 1, color: Color(0x668E877E)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('compose-note-field'),
          controller: _notes,
          focusNode: _noteFocus,
          enabled: !_sending,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(
            fontSize: 15,
            height: 1.45,
            color: MutandeColors.stone800,
          ),
          cursorColor: MutandeColors.stone800,
          decoration: const InputDecoration(
            hintText: 'The note they should act on',
            hintStyle: TextStyle(fontSize: 15, color: MutandeColors.stone400),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _files.length; i++)
                _DispatchFileChip(
                  key: Key('compose-file-chip-${_files[i].path}'),
                  name: _files[i].name,
                  caption: collabFileSizeLabel(_files[i].size),
                  onRemove: _sending
                      ? null
                      : () => setState(() => _files.removeAt(i)),
                ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          PaneInlineError(message: _error!),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              key: const Key('compose-attach-file'),
              tooltip: 'Attach files',
              onPressed: _sending ? null : _attachFiles,
              icon: const Icon(LucideIcons.paperclip, size: 18),
              color: MutandeColors.stone500,
              visualDensity: VisualDensity.compact,
            ),
            const Spacer(),
            IconButton.filled(
              key: const Key('compose-send'),
              tooltip: 'Send',
              onPressed: _canSend ? _send : null,
              icon: _sending
                  ? const MutandeOrb.loading(
                      semanticLabel: 'Sending…',
                      dark: true,
                    )
                  : const Icon(LucideIcons.arrowUp, size: 16),
              style: IconButton.styleFrom(
                backgroundColor: _canSend
                    ? MutandeColors.stone800
                    : const Color(0xFFB7B1A8),
                foregroundColor: _canSend
                    ? MutandeColors.stone50
                    : MutandeColors.stone600,
                disabledBackgroundColor: const Color(0xFFB7B1A8),
                disabledForegroundColor: MutandeColors.stone600,
                minimumSize: const Size(36, 36),
                maximumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DispatchFileChip extends StatelessWidget {
  const _DispatchFileChip({
    super.key,
    required this.name,
    this.caption,
    this.onRemove,
  });

  final String name;
  final String? caption;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final size = caption?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x668E877E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.paperclip,
            size: 14,
            color: MutandeColors.stone500,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(fontSize: 12, color: MutandeColors.stone800),
          ),
          if (size != null && size.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              size,
              style: const TextStyle(fontSize: 11, color: MutandeColors.stone400),
            ),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(LucideIcons.x, size: 14),
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.onTap});

  final String address;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: MutandeColors.stone800,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                address,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: MutandeColors.stone800,
                ),
              ),
            ),
            Text(
              composeAddressHint(address),
              style: const TextStyle(
                fontSize: 12,
                color: MutandeColors.stone400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `alice@acme` / `alice@acme/cursor` → `@all@acme`.
String? orgBroadcastFromHandle(String? handle) {
  if (handle == null || handle.isEmpty) return null;
  final at = handle.lastIndexOf('@');
  if (at < 0 || at >= handle.length - 1) return null;
  var org = handle.substring(at + 1);
  final slash = org.indexOf('/');
  if (slash >= 0) org = org.substring(0, slash);
  if (org.isEmpty) return null;
  return '@all@${org.toLowerCase()}';
}

String? bareHandleFromInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('@') && !trimmed.substring(1).contains('@')) {
    return null;
  }
  final slash = trimmed.indexOf('/');
  final base = slash >= 0 ? trimmed.substring(0, slash) : trimmed;
  final at = base.lastIndexOf('@');
  if (at <= 0 || at >= base.length - 1) return null;
  return base.toLowerCase();
}
