import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../services/daemon_errors.dart';
import '../theme/mutande_macos_theme.dart';
import 'mutande_sheet.dart';
import 'mutande_stagger.dart';
import 'thinking_orb.dart';

Future<String?> showCreateCardSheet({
  required BuildContext context,
  required DaemonClient daemon,
  required String collabId,
  String? laneId,
  String? laneName,
  Rect? origin,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = size.width.clamp(360.0, 420.0);
  final height = (size.height - 200).clamp(240.0, 320.0);
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
    ),
  );
}

/// New-card form — title opens a thread on this collab + lane.
class CreateCardSheet extends StatefulWidget {
  const CreateCardSheet({
    super.key,
    required this.daemon,
    required this.collabId,
    this.laneId,
    this.laneName,
  });

  final DaemonClient daemon;
  final String collabId;
  final String? laneId;
  final String? laneName;

  @override
  State<CreateCardSheet> createState() => _CreateCardSheetState();
}

class _CreateCardSheetState extends State<CreateCardSheet> {
  final _title = TextEditingController();
  bool _busy = false;
  String? _error;

  String? get _laneCaption {
    final name = widget.laneName?.trim();
    if (name == null || name.isEmpty) return null;
    return 'Filed in $name.';
  }

  @override
  void dispose() {
    _title.dispose();
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

  Future<void> _submit() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title this card.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.daemon.createCollabCard(
        collabId: widget.collabId,
        title: title,
        laneId: widget.laneId,
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
    return Material(
      color: MutandeColors.stone50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'New card',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: MutandeColors.stone800,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: MutandeStaggerScope(
                delay: MutandeStaggerScope.sectionStagger,
                child: _form(),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  color: MutandeColors.bronze,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                _CreateButton(busy: _busy, onPressed: _submit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MutandeStaggerIn(
            id: 'title',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Title'),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('card-title-field'),
                  controller: _title,
                  autofocus: true,
                  enabled: !_busy,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: const InputDecoration(
                    hintText: 'e.g. ship invites',
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          if (_laneCaption != null)
            MutandeStaggerIn(
              id: 'lane',
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _laneCaption!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: MutandeColors.stone500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: MutandeColors.stone400,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
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
        minimumSize: const Size(96, 36),
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
          : const Text('Create'),
    );
  }
}
