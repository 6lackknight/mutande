import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../services/daemon_errors.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import 'ai_host_icon.dart';
import 'contact_avatar.dart';
import 'create_collab_sheet.dart';
import 'mutande_sheet.dart';
import 'thinking_orb.dart';

/// True when [address] is this collab's steerer or roster agent.
bool cardAssigneeAllowed(
  String address, {
  required Iterable<String> people,
  required Iterable<String> agents,
}) {
  final a = address.trim().toLowerCase();
  if (a.isEmpty) return false;
  for (final p in people) {
    if (p.trim().toLowerCase() == a) return true;
  }
  for (final ag in agents) {
    if (ag.trim().toLowerCase() == a) return true;
  }
  return false;
}

Future<String?> showCreateCardSheet({
  required BuildContext context,
  required DaemonClient daemon,
  required String collabId,
  String? laneId,
  String? laneName,
  Rect? origin,
  List<String> people = const [],
  List<CollabRosterView> agents = const [],
  String? handle,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = size.width.clamp(400.0, 480.0);
  final height = (size.height - 80).clamp(480.0, 560.0);
  return showMutandeSheet<String>(
    context: context,
    barrierLabel: 'New card',
    origin: origin,
    width: width,
    height: height,
    child: CreateCardSheet(
      daemon: daemon,
      collabId: collabId,
      laneId: laneId,
      laneName: laneName,
      people: people,
      agents: agents,
      handle: handle,
    ),
  );
}

/// New-card envelope — compose as a thread (To / subject / body / attach).
class CreateCardSheet extends StatefulWidget {
  const CreateCardSheet({
    super.key,
    required this.daemon,
    required this.collabId,
    this.laneId,
    this.laneName,
    this.people = const [],
    this.agents = const [],
    this.handle,
    this.pickFiles,
  });

  final DaemonClient daemon;
  final String collabId;
  final String? laneId;
  final String? laneName;
  final List<String> people;
  final List<CollabRosterView> agents;
  final String? handle;
  final Future<List<CollabPendingFile>> Function()? pickFiles;

  @override
  State<CreateCardSheet> createState() => _CreateCardSheetState();
}

class _CreateCardSheetState extends State<CreateCardSheet> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _assignedTo;
  final _files = <CollabPendingFile>[];

  String? get _laneLabel {
    final name = widget.laneName?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  List<String> get _people {
    final seen = <String>{};
    final out = <String>[];
    for (final p in widget.people) {
      final h = p.trim().toLowerCase();
      if (h.isEmpty || seen.contains(h)) continue;
      seen.add(h);
      out.add(h);
    }
    return out;
  }

  List<CollabRosterView> get _agents {
    final seen = <String>{};
    final out = <CollabRosterView>[];
    for (final a in widget.agents) {
      final addr = a.address.trim().toLowerCase();
      if (addr.isEmpty || seen.contains(addr)) continue;
      seen.add(addr);
      out.add(
        CollabRosterView(
          userId: a.userId,
          agentId: a.agentId,
          address: addr,
          transport: a.transport,
        ),
      );
    }
    return out;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _submitErrorCopy(Object e) {
    final lower = e.toString().toLowerCase();
    if (isHubUnimplemented(lower)) {
      return "This hub doesn't support collab yet.";
    }
    final mapped = friendlyDaemonError(e, what: 'New card');
    if (mapped.startsWith("Couldn't load New card")) {
      return mapped.replaceFirst(
        "Couldn't load New card",
        "Couldn't create this card",
      );
    }
    return mapped;
  }

  void _toggleAssignee(String address) {
    final a = address.trim().toLowerCase();
    if (!cardAssigneeAllowed(
      a,
      people: _people,
      agents: _agents.map((e) => e.address),
    )) {
      return;
    }
    setState(() {
      _assignedTo = _assignedTo == a ? null : a;
      _error = null;
    });
  }

  Future<void> _attachFiles() async {
    if (_busy) return;
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

  Future<void> _submit() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give this a subject.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notes = _notes.text.trim();
      final id = await widget.daemon.createCollabCard(
        collabId: widget.collabId,
        title: title,
        notes: notes.isEmpty ? null : notes,
        laneId: widget.laneId,
        assignedTo: _assignedTo,
        artifacts: [
          for (final f in _files)
            {
              'kind': 'file',
              'name': f.name,
              'path': f.path,
              if (f.mime != null && f.mime!.trim().isNotEmpty) 'mime': f.mime,
            },
        ],
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _submitErrorCopy(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lane = _laneLabel;
    return Material(
      color: MutandeColors.stone50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: Row(
              children: [
                const Text(
                  'New card',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: MutandeColors.stone800,
                  ),
                ),
                const Spacer(),
                if (lane != null) _LaneMark(lane),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 36,
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'To',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MutandeColors.stone400,
                      ),
                    ),
                  ),
                ),
                Expanded(child: _toChips()),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: Divider(height: 1, color: MutandeColors.stone200),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
            child: TextField(
              key: const Key('card-title-field'),
              controller: _title,
              autofocus: true,
              enabled: !_busy,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: MutandeColors.stone800,
              ),
              decoration: const InputDecoration(
                hintText: 'Subject',
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
              child: TextField(
                key: const Key('card-notes-field'),
                controller: _notes,
                enabled: !_busy,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: MutandeColors.stone600,
                ),
                decoration: const InputDecoration(
                  hintText: 'First handoff — what should they do?',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _files.length; i++)
                    _FileStamp(
                      key: Key('card-file-chip-${_files[i].path}'),
                      name: _files[i].name,
                      caption: _files[i].sizeLabel,
                      onRemove: _busy
                          ? null
                          : () => setState(() => _files.removeAt(i)),
                    ),
                ],
              ),
            ),
          const Divider(height: 1, color: MutandeColors.stone200),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: MutandeColors.bronze,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 10),
            child: Row(
              children: [
                IconButton(
                  key: const Key('card-attach-file'),
                  tooltip: 'Attach',
                  onPressed: _busy ? null : _attachFiles,
                  icon: const Icon(Icons.attach_file, size: 18),
                  color: MutandeColors.stone500,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                _CreateButton(busy: _busy, onPressed: _submit),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toChips() {
    final people = _people;
    final agents = _agents;
    if (people.isEmpty && agents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Unassigned',
          style: TextStyle(fontSize: 13, color: MutandeColors.stone400),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in people)
          _FaceChip(
            key: Key('card-assignee-$p'),
            handle: p,
            myHandle: widget.handle,
            selected: _assignedTo == p,
            onTap: _busy ? null : () => _toggleAssignee(p),
          ),
        for (final a in agents)
          _FaceChip(
            key: Key('card-assignee-${a.address}'),
            handle: a.address,
            myHandle: widget.handle,
            agent: true,
            selected: _assignedTo == a.address,
            onTap: _busy ? null : () => _toggleAssignee(a.address),
          ),
      ],
    );
  }
}

class _LaneMark extends StatelessWidget {
  const _LaneMark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('card-lane-mark'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: MutandeColors.bronzeSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: MutandeColors.bronze,
        ),
      ),
    );
  }
}

class _FaceChip extends StatelessWidget {
  const _FaceChip({
    super.key,
    required this.handle,
    required this.selected,
    this.myHandle,
    this.agent = false,
    this.onTap,
  });

  final String handle;
  final String? myHandle;
  final bool selected;
  final bool agent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = formatMailAddress(handle, myHandle: myHandle);
    final slug = handle.contains('/')
        ? handle.substring(handle.lastIndexOf('/') + 1)
        : null;
    final mine = myHandle?.trim().toLowerCase();
    final fg = selected ? MutandeColors.stone50 : MutandeColors.stone800;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: MutandeMotion.of(context, MutandeMotion.hover),
          curve: MutandeMotion.easeOut,
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(
            color: selected ? MutandeColors.stone800 : MutandeColors.stone50,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? MutandeColors.stone800 : MutandeColors.stone200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (agent && slug != null && slug.isNotEmpty)
                AiHostIcon(slug, size: 14, showPlate: false)
              else
                PersonAvatar(
                  size: 18,
                  initials: personInitials(titleCaseLocalPart(handle)),
                  seed: handle,
                  isSelf: mine != null && handle == mine,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileStamp extends StatelessWidget {
  const _FileStamp({
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
        color: MutandeColors.stone100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 14,
            color: MutandeColors.stone500,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              color: MutandeColors.stone800,
            ),
          ),
          if (size != null && size.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              size,
              style: const TextStyle(
                fontSize: 11,
                color: MutandeColors.stone400,
              ),
            ),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 14),
          ),
        ],
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? () {} : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(108, 36),
        backgroundColor: MutandeColors.stone800,
        foregroundColor: MutandeColors.stone50,
        disabledBackgroundColor: MutandeColors.stone200,
        shape: const StadiumBorder(),
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: MutandeOrb.standard(
                size: ThinkingOrbSize.inline,
                semanticLabel: 'Creating',
              ),
            )
          : const Text('File card'),
    );
  }
}
