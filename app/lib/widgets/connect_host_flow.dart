import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_events.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import '../theme/mutande_macos_theme.dart';
import 'ai_host_icon.dart';
import 'onboarding_chrome.dart';
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
  bool needsInstall = false,
  String? downloadUrl,
  Rect? morphOrigin,
  bool fullScreen = false,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final dialog = _ConnectHostFlowDialog(
    daemon: daemon,
    hostLinkStore: hostLinkStore,
    host: host,
    celebrateFirstHost: celebrateFirstHost,
    needsInstall: needsInstall,
    downloadUrl: downloadUrl,
    useIconHero: morphOrigin != null && !reduceMotion,
    embedded: fullScreen,
  );

  if (fullScreen) {
    return Navigator.of(context).push<ConnectHostFlowResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: const Color(0xFFFAFAF9),
          body: SafeArea(child: dialog),
        ),
      ),
    );
  }

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
    transitionDuration: MutandeMotion.ui,
    pageBuilder: (ctx, animation, secondary) => dialog,
    transitionBuilder: (ctx, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: MutandeMotion.easeOut,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          alignment: alignment,
          child: child,
        ),
      );
    },
  );
}

enum _Step { install, mcp, skill, done }

class _ConnectHostFlowDialog extends StatefulWidget {
  const _ConnectHostFlowDialog({
    required this.daemon,
    required this.hostLinkStore,
    required this.host,
    required this.celebrateFirstHost,
    this.needsInstall = false,
    this.downloadUrl,
    this.useIconHero = false,
    this.embedded = false,
  });

  final DaemonClient daemon;
  final HostLinkStore hostLinkStore;
  final String host;
  final bool celebrateFirstHost;
  final bool needsInstall;
  final String? downloadUrl;
  final bool useIconHero;
  final bool embedded;

  @override
  State<_ConnectHostFlowDialog> createState() => _ConnectHostFlowDialogState();
}

class _ConnectHostFlowDialogState extends State<_ConnectHostFlowDialog> {
  _Step _step = _Step.mcp;
  bool _busy = true;
  String? _error;
  String? _mcpHint;
  InstallSkillResult? _skill;
  SkillLinkStatus _skillStatus = SkillLinkStatus.none;

  @override
  void initState() {
    super.initState();
    if (widget.needsInstall) {
      _step = _Step.install;
      _busy = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runMcp());
    }
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
        Analytics.track(AnalyticsEvent.connectMcpFailure, {
          'host': widget.host.toLowerCase(),
        });
        setState(() {
          _busy = false;
          _error = write?.note?.trim().isNotEmpty == true
              ? write!.note!.trim()
              : 'Could not write MCP config.';
          _mcpHint = _restartHint(widget.host);
        });
        return;
      }
      Analytics.track(AnalyticsEvent.connectMcpSuccess, {
        'host': widget.host.toLowerCase(),
      });
      setState(() {
        _busy = false;
        _mcpHint = write!.note?.trim().isNotEmpty == true
            ? write.note!.trim()
            : _restartHint(widget.host);
      });
      if (!mounted) return;
      await _runSkill();
    } catch (e) {
      if (!mounted) return;
      Analytics.track(AnalyticsEvent.connectMcpFailure, {
        'host': widget.host.toLowerCase(),
      });
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
      if (skill.ok) {
        Analytics.track(AnalyticsEvent.connectSkillSuccess, {
          'host': widget.host.toLowerCase(),
          'mode': skill.mode,
        });
      } else {
        Analytics.track(AnalyticsEvent.connectSkillFailure, {
          'host': widget.host.toLowerCase(),
          'mode': skill.mode,
        });
      }
    } catch (e) {
      if (!mounted) return;
      final hint = friendlyDaemonError(e, what: 'Skill install');
      Analytics.track(AnalyticsEvent.connectSkillFailure, {
        'host': widget.host.toLowerCase(),
      });
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
      final prev = (await widget.hostLinkStore
          .load())[widget.host.toLowerCase()];
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
      const SnackBar(
        content: Text('Copied'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _reveal(String path) async {
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reveal $path')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = AiHostIcon.displayName(widget.host);
    final showSkillActions =
        _step == _Step.skill &&
        !_busy &&
        (_skillStatus == SkillLinkStatus.needsSetup ||
            (_skill?.isManual ?? false));

    final body = AnimatedSwitcher(
      duration: Duration(milliseconds: _reduceMotion ? 0 : 200),
      switchInCurve: MutandeMotion.easeOut,
      switchOutCurve: MutandeMotion.easeOut,
      layoutBuilder: (current, previous) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [...previous, ?current],
        );
      },
      child: KeyedSubtree(
        key: ValueKey('${_step}_$_busy$_error$_skillStatus'),
        child: _body(label, showSkillActions),
      ),
    );

    final letterhead = _ConnectLetterhead(
      host: widget.host,
      label: label,
      step: _step,
      needsInstall: widget.needsInstall,
      useIconHero: widget.useIconHero,
    );

    if (widget.embedded) {
      return ColoredBox(
        color: MutandeColors.stone50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OnboardingSpace.xl,
                OnboardingSpace.xl + OnboardingSpace.titlebar,
                OnboardingSpace.xl,
                OnboardingSpace.lg,
              ),
              child: letterhead,
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: MutandeColors.stone200,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  OnboardingSpace.xl,
                  OnboardingSpace.xxl,
                  OnboardingSpace.xl,
                  OnboardingSpace.xl,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: body,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: MutandeColors.stone50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OnboardingSpace.lg,
                OnboardingSpace.lg,
                OnboardingSpace.lg,
                OnboardingSpace.md,
              ),
              child: letterhead,
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: MutandeColors.stone200,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  OnboardingSpace.lg,
                  OnboardingSpace.lg,
                  OnboardingSpace.lg,
                  OnboardingSpace.lg,
                ),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(String label, bool showSkillActions) {
    if (_step == _Step.done) {
      return OnboardingHeading(
        variant: OnboardingHeadingVariant.display,
        title: '$label will check mutande mail on new chats.',
      );
    }

    if (_step == _Step.install) {
      final url = widget.downloadUrl;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Install $label on this Mac.',
            subtitle:
                'Open the download page, install the app, then come back. '
                'mutande will write the relay next.',
          ),
          OnboardingActions(
            primary: FilledButton(
              onPressed: _runMcp,
              child: const Text('I’ve installed it'),
            ),
            secondary: url == null
                ? TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  )
                : TextButton(
                    onPressed: () => Process.run('open', [url]),
                    child: const Text('Open download'),
                  ),
            tertiary: url == null
                ? null
                : TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
          ),
        ],
      );
    }

    if (_busy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MutandeOrb.standard(semanticLabel: 'Working…'),
          const SizedBox(height: OnboardingSpace.lg),
          OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: _step == _Step.mcp
                ? 'Writing the relay…'
                : 'Placing the skill…',
          ),
        ],
      );
    }

    if (_step == _Step.mcp && _error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'The relay didn’t write.',
          ),
          const SizedBox(height: OnboardingSpace.md),
          OnboardingErrorBanner(message: _error!),
          if (_mcpHint != null) ...[
            const SizedBox(height: OnboardingSpace.sm),
            Text(
              _mcpHint!,
              style: const TextStyle(
                color: MutandeColors.stone500,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          OnboardingActions(
            primary: FilledButton(
              onPressed: _runMcp,
              child: const Text('Retry'),
            ),
            secondary: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      );
    }

    if (_step == _Step.mcp) {
      return OnboardingHeading(
        variant: OnboardingHeadingVariant.display,
        title: 'The relay is written.',
        subtitle: _mcpHint,
      );
    }

    if (_skillStatus == SkillLinkStatus.installed) {
      final zip = _skill?.zipPath;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'The skill is in place.',
            subtitle: _skill?.hint ??
                'This host will check mutande mail when you start a chat. '
                    'If you’re caught up, it stays quiet.',
          ),
          OnboardingActions(
            primary: FilledButton(
              onPressed: () => _finish(SkillLinkStatus.installed),
              child: const Text('Continue'),
            ),
            secondary: zip == null
                ? null
                : TextButton(
                    onPressed: () => _reveal(zip),
                    child: const Text('Reveal ZIP'),
                  ),
            tertiary: zip == null
                ? null
                : TextButton(
                    onPressed: () => _copyPath(zip),
                    child: const Text('Copy ZIP path'),
                  ),
          ),
        ],
      );
    }

    final zip = _skill?.zipPath;
    final path = _skill?.path;
    final hint =
        _skill?.hint ??
        'Couldn’t place the skill automatically. Nothing’s broken — Retry or place it yourself.';
    final copyStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: MutandeColors.stone600,
      height: 1.45,
      fontSize: 15,
    );

    final fileLinks = <Widget>[
      if (zip != null) ...[
        _skillLink(label: 'Reveal ZIP', onPressed: () => _reveal(zip)),
        _skillLink(label: 'Copy ZIP path', onPressed: () => _copyPath(zip)),
      ] else if (path != null) ...[
        _skillLink(label: 'Copy path', onPressed: () => _copyPath(path)),
        _skillLink(
          label: 'Reveal in Finder',
          onPressed: () => _reveal(path.split(';').first.trim()),
        ),
      ],
    ];
    final flowLinks = <Widget>[
      _skillLink(label: 'Retry install', onPressed: _runSkill),
      _skillLink(
        label: 'Skip for now',
        onPressed: () => _finish(SkillLinkStatus.skipped),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Place the skill yourself.',
        ),
        const SizedBox(height: OnboardingSpace.sm),
        Text(
          'This skill teaches the host to check mutande mail when you start a chat. '
          'If you’re caught up, it stays quiet.',
          style: copyStyle,
        ),
        const SizedBox(height: OnboardingSpace.sm),
        Text(hint, style: copyStyle),
        OnboardingActions(
          topSpacing: OnboardingSpace.xxl,
          primary: FilledButton(
            onPressed: () => _finish(SkillLinkStatus.needsSetup),
            child: Text(
              showSkillActions && (_skill?.isManual ?? false)
                  ? 'I’ve added the skill'
                  : 'Continue',
            ),
          ),
        ),
        const SizedBox(height: OnboardingSpace.lg),
        _SkillLinkRows(
          rows: [
            if (fileLinks.isNotEmpty) fileLinks,
            flowLinks,
          ],
        ),
      ],
    );
  }

  Widget _skillLink({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: MutandeColors.bronze,
        disabledForegroundColor: MutandeColors.stone400,
        padding: const EdgeInsets.symmetric(vertical: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return MutandeColors.bronze.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return MutandeColors.bronze.withValues(alpha: 0.08);
          }
          return null;
        }),
      ),
      child: Text(label),
    );
  }
}

/// Same letterhead grammar as the address rail: a Menlo name, then
/// `Step N of 2 — {MCP|Skill}`. No green chips — the headline below says done.
class _ConnectLetterhead extends StatelessWidget {
  const _ConnectLetterhead({
    required this.host,
    required this.label,
    required this.step,
    required this.useIconHero,
    this.needsInstall = false,
  });

  final String host;
  final String label;
  final _Step step;
  final bool useIconHero;
  final bool needsInstall;

  @override
  Widget build(BuildContext context) {
    const iconSize = 28.0;
    final icon = AiHostIcon(host, size: iconSize);
    final total = needsInstall ? 3 : 2;
    final (index, name) = switch (step) {
      _Step.install => (1, 'Install'),
      _Step.mcp => (needsInstall ? 2 : 1, 'MCP'),
      _Step.skill => (needsInstall ? 3 : 2, 'Skill'),
      _Step.done => (total, 'Done'),
    };
    final caption = step == _Step.done
        ? 'Done'
        : 'Step $index of $total — $name';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            useIconHero
                ? Hero(
                    tag: connectHostIconHeroTag(host),
                    child: Material(
                      type: MaterialType.transparency,
                      child: icon,
                    ),
                  )
                : icon,
            const SizedBox(width: OnboardingSpace.sm),
            Flexible(
              child: Text(
                label.toLowerCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 22,
                  height: 1.1,
                  letterSpacing: -0.4,
                  color: MutandeColors.stone800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnboardingSpace.xs),
        Padding(
          // Sit the step under the name, not the mark.
          padding: const EdgeInsets.only(left: iconSize + OnboardingSpace.sm),
          child: Text(
            caption,
            style: const TextStyle(
              color: MutandeColors.stone500,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Two even rows of quiet text links — ZIP helpers, then flow controls.
class _SkillLinkRows extends StatelessWidget {
  const _SkillLinkRows({required this.rows});

  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == rows.length - 1 ? 0 : OnboardingSpace.xs,
            ),
            child: Wrap(
              spacing: OnboardingSpace.lg,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: rows[i],
            ),
          ),
      ],
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
