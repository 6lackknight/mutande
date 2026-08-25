import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_gate.dart';
import '../theme/mutande_macos_theme.dart';
import 'morphing_orb_button.dart';

/// Blocks or nags until the user reinstalls a newer desktop build.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.latest,
    required this.onRecheck,
    this.onSkip,
    this.skippable = false,
    this.rechecking = false,
    this.recheckError,
    this.cpu,
  });

  final String currentVersion;
  final DesktopVersionInfo latest;
  final Future<void> Function() onRecheck;
  final VoidCallback? onSkip;
  final bool skippable;
  final bool rechecking;
  final String? recheckError;
  final DesktopCpu? cpu;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;

  DesktopCpu get _cpu => widget.cpu ?? DesktopCpu.detect();

  Future<void> _openDownload() async {
    if (_opening || widget.rechecking) return;
    setState(() => _opening = true);
    final url = widget.latest.preferredDownloadUrl(cpu: _cpu);
    try {
      if (!kIsWeb && Platform.isMacOS) {
        await Process.run('open', [url]);
        return;
      }
      if (!kIsWeb && Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
        return;
      }
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied download link: $url')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.latest.version;
    final current = widget.currentVersion;
    final busy = widget.rechecking || _opening;
    final skippable = widget.skippable && widget.onSkip != null;
    final title = skippable ? 'Update available' : 'Update required';
    final body = skippable
        ? 'mutande $latest (${widget.latest.channel}) is available. '
            'You’re on v$current — reinstall when you can, or skip this cut.'
        : 'mutande $latest (${widget.latest.channel}) is required. '
            'You’re on v$current — reinstall to keep using the alpha.';

    return Scaffold(
      backgroundColor: MutandeColors.stone100,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.system_update_alt_outlined,
                    size: 40,
                    color: MutandeColors.bronze.withValues(alpha: 0.9),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'mutande',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: MutandeColors.stone800,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: MutandeColors.stone800,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: MutandeColors.stone600,
                          height: 1.45,
                        ),
                  ),
                  if (widget.recheckError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      widget.recheckError!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: MutandeColors.stone500,
                          ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  MorphingOrbButton(
                    label: widget.latest.downloadButtonLabel(cpu: _cpu),
                    loading: _opening,
                    loadingLabel: 'Opening…',
                    onPressed: busy ? null : _openDownload,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: busy ? null : widget.onRecheck,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MutandeColors.stone800,
                        side: const BorderSide(color: MutandeColors.stone200),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.rechecking ? 'Checking…' : 'Check again',
                      ),
                    ),
                  ),
                  if (skippable) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy ? null : widget.onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: MutandeColors.stone500,
                        minimumSize: const Size.fromHeight(40),
                      ),
                      child: const Text('Skip this version'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
