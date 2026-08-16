import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import '../../util/address_display.dart';
import '../../util/clock_format.dart';
import '../../util/thread_peer.dart';
import '../contact_avatar.dart';
import '../create_collab_sheet.dart' show collabInstructionsVisible;
import '../mutande_stagger.dart';

/// Brain pane — Side rail: standing instructions on a bronze left rail,
/// learnings + capsule on the right.
class CollabBrainPane extends StatefulWidget {
  const CollabBrainPane({
    super.key,
    required this.daemon,
    required this.collab,
    required this.onChanged,
    this.handle,
    this.userId,
    this.avatarUrls = const {},
  });

  final DaemonClient daemon;
  final CollabDetail collab;
  final VoidCallback onChanged;
  final String? handle;
  final String? userId;
  final Map<String, String> avatarUrls;

  @override
  State<CollabBrainPane> createState() => _CollabBrainPaneState();
}

class _CollabBrainPaneState extends State<CollabBrainPane> {
  late final TextEditingController _instructions;
  final _learning = TextEditingController();
  bool _saving = false;
  bool _editing = false;
  String _snapshot = '';

  @override
  void initState() {
    super.initState();
    _instructions = TextEditingController(
      text: widget.collab.instructions ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant CollabBrainPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.collab.instructions ?? '';
    if (next != _instructions.text &&
        next != (oldWidget.collab.instructions ?? '')) {
      _instructions.text = next;
    }
  }

  @override
  void dispose() {
    _instructions.dispose();
    _learning.dispose();
    super.dispose();
  }

  bool get _isCreator =>
      widget.collab.isCreator(userId: widget.userId, handle: widget.handle);

  bool get _canEditInstructions =>
      _isCreator && !widget.collab.isE2e && !widget.collab.isArchived;

  Future<void> _saveInstructions() async {
    if (!_canEditInstructions) return;
    setState(() => _saving = true);
    try {
      await widget.daemon.updateCollabInstructions(
        collabId: widget.collab.id,
        instructions: _instructions.text,
      );
      widget.onChanged();
      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addLearning() async {
    if (widget.collab.isArchived) return;
    final notes = _learning.text.trim();
    if (notes.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.daemon.addLearning(collabId: widget.collab.id, notes: notes);
      _learning.clear();
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collab = widget.collab;
    final showInstructions = collabInstructionsVisible(
      steerers: collab.steererHandles.isNotEmpty
          ? collab.steererHandles
          : [if (widget.handle != null) widget.handle!],
      roster: collab.roster.map((r) => r.address),
    );
    final learnings = collab.learnings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showInstructions)
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _QuoteRail(
                text: _instructionCopy(
                  text: _instructions.text,
                  e2e: collab.isE2e,
                  archived: collab.isArchived,
                ),
                empty: _instructions.text.trim().isEmpty,
                isCreator: _isCreator,
                canEdit: _canEditInstructions,
                editing: _editing,
                controller: _instructions,
                saving: _saving,
                onEdit: () {
                  _snapshot = _instructions.text;
                  setState(() => _editing = true);
                },
                onCancel: () {
                  _instructions.text = _snapshot;
                  setState(() => _editing = false);
                },
                onSave: _saveInstructions,
              ),
            ),
          ),
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(
                child: learnings.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'No learnings yet.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: MutandeColors.stone400,
                            ),
                          ),
                        ),
                      )
                    : MutandeStaggerScope(
                        key: ValueKey(collab.id),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: learnings.length,
                          itemBuilder: (context, i) {
                            final l = learnings[i];
                            return MutandeStaggerIn(
                              key: ValueKey(l.id),
                              id: l.id,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LearningStamp(
                                  learning: l,
                                  myHandle: widget.handle,
                                  avatarUrl: widget
                                      .avatarUrls[bareMailHandle(l.fromHandle)],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: _CapsuleComposer(
                  controller: _learning,
                  saving: _saving,
                  archived: collab.isArchived,
                  onSend: collab.isArchived ? null : _addLearning,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _instructionCopy({
  required String text,
  required bool e2e,
  required bool archived,
}) {
  final body = text.trim();
  if (body.isNotEmpty) return body;
  if (archived) return 'Archived — unarchive to edit instructions.';
  if (e2e) return 'E2E instructions stay sealed on this device.';
  return 'No standing instructions yet.';
}

class _QuoteRail extends StatelessWidget {
  const _QuoteRail({
    required this.text,
    required this.empty,
    required this.isCreator,
    required this.canEdit,
    required this.editing,
    required this.controller,
    required this.saving,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  final String text;
  final bool empty;
  final bool isCreator;
  final bool canEdit;
  final bool editing;
  final TextEditingController controller;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MutandeColors.bronzeSoft,
        border: Border(right: BorderSide(color: MutandeColors.stone200)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (canEdit && !editing)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('collab-brain-instructions-edit'),
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: MutandeColors.bronze,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Edit',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            const Text(
              '“',
              style: TextStyle(
                fontSize: 32,
                height: 0.8,
                color: MutandeColors.bronze,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (editing && canEdit)
              Expanded(
                child: SingleChildScrollView(
                  child: _CreatorEditor(
                    controller: controller,
                    saving: saving,
                    onSave: onSave,
                    onCancel: onCancel,
                  ),
                ),
              )
            else
              Expanded(
                child: Text(
                  text,
                  key: canEdit
                      ? null
                      : const Key('collab-brain-instructions-letter'),
                  maxLines: 12,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                    color: empty
                        ? MutandeColors.stone500
                        : MutandeColors.stone800,
                  ),
                ),
              ),
            if (!isCreator && !editing) ...[
              const SizedBox(height: 10),
              const Text(
                'Only the creator can change instructions.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w400,
                  color: MutandeColors.stone400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreatorEditor extends StatelessWidget {
  const _CreatorEditor({
    required this.controller,
    required this.saving,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('collab-brain-instructions-field'),
          controller: controller,
          maxLines: 8,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w400,
            color: MutandeColors.stone800,
          ),
          decoration: const InputDecoration(
            hintText: 'Standing context for this board',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: MutandeColors.stone500,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              key: const Key('collab-brain-instructions-save'),
              onPressed: saving ? null : onSave,
              style: TextButton.styleFrom(
                foregroundColor: MutandeColors.amber,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LearningStamp extends StatelessWidget {
  const _LearningStamp({required this.learning, this.myHandle, this.avatarUrl});

  final CollabLearningView learning;
  final String? myHandle;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final notes = learning.notes?.trim();
    final body = notes?.isNotEmpty == true ? notes! : 'Sealed learning';
    final handle = bareMailHandle(learning.fromHandle);
    final who = formatMailAddress(learning.fromHandle, myHandle: myHandle);
    final when = formatRelativeTime(learning.createdAt);
    final me = myHandle == null || myHandle!.trim().isEmpty
        ? null
        : bareMailHandle(myHandle!);
    return Container(
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MutandeColors.stone200),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: MutandeColors.stone200),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      body,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.25,
                        color: MutandeColors.stone800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (handle.isNotEmpty) ...[
                          PersonAvatar(
                            size: 18,
                            initials: personInitials(
                              titleCaseLocalPart(handle),
                            ),
                            url: avatarUrl,
                            seed: handle,
                            isSelf: me != null && handle == me,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            [
                              who,
                              if (when.isNotEmpty) when,
                            ].where((s) => s.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: MutandeColors.stone400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapsuleComposer extends StatefulWidget {
  const _CapsuleComposer({
    required this.controller,
    required this.saving,
    required this.archived,
    this.onSend,
  });

  final TextEditingController controller;
  final bool saving;
  final bool archived;
  final VoidCallback? onSend;

  @override
  State<_CapsuleComposer> createState() => _CapsuleComposerState();
}

class _CapsuleComposerState extends State<_CapsuleComposer> {
  bool _focused = false;
  bool _press = false;
  late bool _hasText = widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.archived && !widget.saving;
    final canSend = enabled && _hasText && widget.onSend != null;
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: MutandeMotion.of(context, MutandeMotion.hover),
        curve: MutandeMotion.easeOut,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MutandeColors.stone100,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _focused ? MutandeColors.stone800 : MutandeColors.stone200,
            width: _focused ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 3,
                  cursorColor: MutandeColors.stone800,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    color: MutandeColors.stone800,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.archived
                        ? 'Archived — unarchive to add a learning'
                        : 'A one-line learning',
                    hintStyle: const TextStyle(
                      color: MutandeColors.stone400,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) {
                    if (canSend) widget.onSend?.call();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Listener(
                onPointerDown: canSend
                    ? (_) => setState(() => _press = true)
                    : null,
                onPointerUp: (_) => setState(() => _press = false),
                onPointerCancel: (_) => setState(() => _press = false),
                child: AnimatedScale(
                  scale: _press ? 0.92 : 1,
                  duration: MutandeMotion.of(context, MutandeMotion.hover),
                  curve: MutandeMotion.easeOut,
                  child: IconButton.filled(
                    tooltip: 'Add learning',
                    onPressed: canSend ? widget.onSend : null,
                    icon: const Icon(LucideIcons.arrowUp, size: 15),
                    style: IconButton.styleFrom(
                      backgroundColor: canSend
                          ? MutandeColors.stone800
                          : MutandeColors.stone200,
                      foregroundColor: canSend
                          ? MutandeColors.stone50
                          : MutandeColors.stone400,
                      disabledBackgroundColor: MutandeColors.stone200,
                      disabledForegroundColor: MutandeColors.stone400,
                      minimumSize: const Size(32, 32),
                      maximumSize: const Size(32, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
