import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import 'ai_host_icon.dart';
import 'thinking_orb.dart';

/// Outcome of the 2-step MCP → skill connect flow.
class ConnectHostFlowResult {
  const ConnectHostFlowResult({
    required this.host,
    required this.mcpOk,
    required this.skillStatus,
    this.mcpNote,
  });

  final String host;
  final bool mcpOk;
  final SkillLinkStatus skillStatus;
  final String? mcpNote;
}

/// Hero tag for host icon shared between Settings tile and connect dialog.
String connectHostIconHeroTag(String host) =>
    'mutande-connect-host-icon-${host.toLowerCase()}';

/// Run the quiet-courier 2-step host link dialog for [host].
///
/// When [morphOrigin] is set (and motion is allowed), the dialog scales out
/// from that tile rect — shared-element feel without a package dependency.
///
/// Returns null if the user dismisses before MCP succeeds.
Future<ConnectHostFlowResult?> showConnectHostFlow({
  required BuildContext context,
  required DaemonClient daemon,
  required HostLinkStore hostLinkStore,
  required String host,
  bool celebrateFirstHost = false,
  Rect? morphOrigin,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final dialog = _ConnectHostFlowDialog(
    daemon: daemon,
    hostLinkStore: hostLinkStore,
    host: host,
    celebrateFirstHost: celebrateFirstHost,
    useIconHero: morphOrigin != null && !reduceMotion,
  );

  if (morphOrigin == null || reduceMotion) {
    return showDialog<ConnectHostFlowResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x660C0A09),
      builder: (ctx) => dialog,
    );
  }

  final screen = MediaQuery.sizeOf(context);
  final alignment = Alignment(
    ((morphOrigin.center.dx / screen.width) * 2 - 1).clamp(-1.0, 1.0),
    ((morphOrigin.center.dy / screen.height) * 2 - 1).clamp(-1.0, 1.0),
  );

  return showGeneralDialog<ConnectHostFlowResult>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Connect AI host',
    barrierColor: const Color(0x660C0A09),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, animation, secondary) => dialog,
    transitionBuilder: (ctx, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.78, end: 1).animate(curved),
          alignment: alignment,
          child: child,
        ),
      );
    },
  );
}

enum _Step { mcp, skill, done }

class _ConnectHostFlowDialog extends StatefulWidget {
  const _ConnectHostFlowDialog({
    required this.daemon,
    required this.hostLinkStore,
    required this.host,
    required this.celebrateFirstHost,
    this.useIconHero = false,
  });

  final DaemonClient daemon;
  final HostLinkStore hostLinkStore;
  final String host;
  final bool celebrateFirstHost;
  final bool useIconHero;

  @override
  State<_ConnectHostFlowDialog> createState() => _ConnectHostFlowDialogState();
}

class _ConnectHostFlowDialogState extends State<_ConnectHostFlowDialog>
    with SingleTickerProviderStateMixin {
  _Step _step = _Step.mcp;
  bool _busy = true;
  String? _error;
  String? _mcpHint;
  InstallSkillResult? _skill;
  SkillLinkStatus _skillStatus = SkillLinkStatus.none;
  late final AnimationController _checkCtrl;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _runMcp());
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    super.dispose();
  }

  bool get _reduceMotion {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  Future<void> _runMcp() async {
    setState(() {
      _step = _Step.mcp;
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.daemon.connectHost(widget.host);
      HostWriteResult? write;
      for (final h in result.hosts) {
        if (h.host.toLowerCase() == widget.host.toLowerCase()) {
          write = h;
          break;
        }
      }
      write ??= result.hosts.isNotEmpty ? result.hosts.first : null;
      if (write != null) {
        await widget.hostLinkStore.record(write);
      }
      if (!mounted) return;
      if (write == null || !write.ok) {
        setState(() {
          _busy = false;
          _error = write?.note?.trim().isNotEmpty == true
              ? write!.note!.trim()
              : 'Could not write MCP config.';
          _mcpHint = _restartHint(widget.host);
        });
        return;
      }
      setState(() {
        _busy = false;
        _mcpHint = write!.note?.trim().isNotEmpty == true
            ? write.note!.trim()
            : _restartHint(widget.host);
      });
      if (!_reduceMotion) {
        await _checkCtrl.forward(from: 0);
      }
      await Future<void>.delayed(
        Duration(milliseconds: _reduceMotion ? 80 : 280),
      );
      if (!mounted) return;
      await _runSkill();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyDaemonError(e, what: 'Connect');
      });
    }
  }

  Future<void> _runSkill() async {
    setState(() {
      _step = _Step.skill;
      _busy = true;
      _error = null;
      _skill = null;
    });
    try {
      final skill = await widget.daemon.installSkill(widget.host);
      if (!mounted) return;
      final status = skill.ok
          ? SkillLinkStatus.installed
          : SkillLinkStatus.needsSetup;
      await widget.hostLinkStore.recordSkill(
        host: widget.host,
        status: status,
        path: skill.path,
        zipPath: skill.zipPath,
        hint: skill.hint,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _skill = skill;
        _skillStatus = status;
      });
      if (skill.ok && !_reduceMotion) {
        await _checkCtrl.forward(from: 0);
      }
    } catch (e) {
      if (!mounted) return;
      final hint = friendlyDaemonError(e, what: 'Skill install');
      await widget.hostLinkStore.recordSkill(
        host: widget.host,
        status: SkillLinkStatus.needsSetup,
        hint: hint,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _skillStatus = SkillLinkStatus.needsSetup;
        _skill = InstallSkillResult(
          host: widget.host,
          ok: false,
          mode: 'auto',
          hint: hint,
        );
      });
    }
  }

  Future<void> _finish(SkillLinkStatus status) async {
    if (status == SkillLinkStatus.skipped ||
        status == SkillLinkStatus.installed ||
        status == SkillLinkStatus.needsSetup) {
      final prev = (await widget.hostLinkStore.load())[widget.host.toLowerCase()];
      await widget.hostLinkStore.recordSkill(
        host: widget.host,
        status: status,
        path: prev?.skillPath ?? _skill?.path,
        zipPath: prev?.skillZipPath ?? _skill?.zipPath,
        hint: prev?.skillHint ?? _skill?.hint,
      );
    }
    if (!mounted) return;
    if (widget.celebrateFirstHost &&
        status != SkillLinkStatus.none &&
        !_reduceMotion) {
      setState(() => _step = _Step.done);
      await Future<void>.delayed(const Duration(milliseconds: 520));
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      ConnectHostFlowResult(
        host: widget.host,
        mcpOk: true,
        skillStatus: status,
        mcpNote: _mcpHint,
      ),
    );
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(milliseconds: 800)),
    );
  }

  Future<void> _reveal(String path) async {
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reveal $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = AiHostIcon.displayName(widget.host);
    final showSkillActions = _step == _Step.skill &&
        !_busy &&
        (_skillStatus == SkillLinkStatus.needsSetup ||
            (_skill?.isManual ?? false));

    return Dialog(
      backgroundColor: const Color(0xFFFAFAF9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: widget.useIconHero
                    ? Hero(
                        tag: connectHostIconHeroTag(widget.host),
                        child: Material(
                          type: MaterialType.transparency,
                          child: AiHostIcon(widget.host, size: 48),
                        ),
                      )
                    : AiHostIcon(widget.host, size: 48),
              ),
              const SizedBox(height: 12),
              Text(
                'Connect $label',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF292524),
                ),
              ),
              const SizedBox(height: 16),
              _StepRail(
                step: _step,
                mcpDone: _step == _Step.skill ||
                    _step == _Step.done ||
                    (_step == _Step.mcp && !_busy && _error == null),
                skillDone: _skillStatus == SkillLinkStatus.installed ||
                    _step == _Step.done,
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: Duration(milliseconds: _reduceMotion ? 0 : 220),
                child: KeyedSubtree(
                  key: ValueKey('${_step}_$_busy$_error$_skillStatus'),
                  child: _body(theme, label, showSkillActions),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, String label, bool showSkillActions) {
    if (_step == _Step.done) {
      return Column(
        key: const ValueKey('done'),
        children: [
          Icon(Icons.check_circle_outline, size: 40, color: const Color(0xFF166534)),
          const SizedBox(height: 12),
          Text(
            'Relay linked',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF292524),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$label will check mutande mail on new chats.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF78716C),
            ),
          ),
        ],
      );
    }

    if (_busy) {
      return Column(
        children: [
          const MutandeOrb.standard(semanticLabel: 'Working…'),
          const SizedBox(height: 16),
          Text(
            _step == _Step.mcp
                ? 'Linking the relay…'
                : 'Placing the collaboration skill…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF57534E),
            ),
          ),
        ],
      );
    }

    if (_step == _Step.mcp && _error != null) {
      return Column(
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF991B1B),
            ),
          ),
          if (_mcpHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _mcpHint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF78716C),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _runMcp,
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (_step == _Step.mcp) {
      return Column(
        children: [
          _SoftCheck(controller: _checkCtrl, reduceMotion: _reduceMotion),
          const SizedBox(height: 12),
          Text(
            'MCP linked.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF166534),
            ),
          ),
          if (_mcpHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _mcpHint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFA8A29E),
              ),
            ),
          ],
        ],
      );
    }

    // Skill step
    if (_skillStatus == SkillLinkStatus.installed) {
      return Column(
        children: [
          _SoftCheck(controller: _checkCtrl, reduceMotion: _reduceMotion),
          const SizedBox(height: 12),
          Text(
            'Skill ready.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF166534),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This host will check mutande mail when you start a chat. '
            'If you’re caught up, it stays quiet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF78716C),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => _finish(SkillLinkStatus.installed),
            child: const Text('Continue'),
          ),
        ],
      );
    }

    // needs setup / manual
    final zip = _skill?.zipPath;
    final path = _skill?.path;
    final hint = _skill?.hint ??
        'Couldn’t place the skill automatically. Nothing’s broken — Retry or place it yourself.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This skill teaches the host to check mutande mail when you start a chat. '
          'If you’re caught up, it stays quiet.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF57534E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF44403C),
              height: 1.4,
            ),
          ),
        ),
        if (zip != null || path != null) ...[
          const SizedBox(height: 12),
          if (zip != null)
            OutlinedButton.icon(
              onPressed: () => _reveal(zip),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Reveal ZIP'),
            ),
          if (zip != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copyPath(zip),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy ZIP path'),
            ),
          ],
          if (path != null && zip == null) ...[
            OutlinedButton.icon(
              onPressed: () => _copyPath(path),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy path'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _reveal(path.split(';').first.trim()),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Reveal in Finder'),
            ),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _runSkill,
          child: const Text('Retry install'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => _finish(SkillLinkStatus.needsSetup),
          child: Text(
            showSkillActions && (_skill?.isManual ?? false)
                ? 'I’ve added the skill'
                : 'Continue',
          ),
        ),
        TextButton(
          onPressed: () => _finish(SkillLinkStatus.skipped),
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.step,
    required this.mcpDone,
    required this.skillDone,
  });

  final _Step step;
  final bool mcpDone;
  final bool skillDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepChip(
          label: '1 MCP',
          active: step == _Step.mcp,
          done: mcpDone,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            width: 16,
            height: 1,
            color: const Color(0xFFD6D3D1),
          ),
        ),
        _StepChip(
          label: '2 Skill',
          active: step == _Step.skill || step == _Step.done,
          done: skillDone,
        ),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFF166534)
        : active
            ? const Color(0xFF292524)
            : const Color(0xFFA8A29E);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done)
          const Icon(Icons.check, size: 14, color: Color(0xFF166534))
        else
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF292524) : const Color(0xFFD6D3D1),
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active || done ? FontWeight.w600 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SoftCheck extends StatelessWidget {
  const _SoftCheck({required this.controller, required this.reduceMotion});

  final AnimationController controller;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return const Icon(Icons.check_circle, size: 36, color: Color(0xFF166534));
    }
    return ScaleTransition(
      scale: CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
      child: const Icon(Icons.check_circle, size: 36, color: Color(0xFF166534)),
    );
  }
}

String _restartHint(String host) {
  switch (host.toLowerCase()) {
    case 'cursor':
      return 'Reload MCP in Cursor (or restart Cursor) so it loads the new config.';
    case 'claude':
      return 'Quit and reopen Claude Desktop so it loads the new MCP config.';
    case 'chatgpt':
      return 'Quit and reopen ChatGPT Desktop so it loads the new MCP config.';
    default:
      return 'Restart the host so it loads the mutande MCP server.';
  }
}
