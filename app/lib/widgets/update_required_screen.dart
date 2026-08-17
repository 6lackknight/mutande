import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_gate.dart';
import '../theme/mutande_macos_theme.dart';
import 'morphing_orb_button.dart';

/// Blocks the alpha shell until the user reinstalls a newer desktop build.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.latest,
    required this.onRecheck,
    this.rechecking = false,
    this.recheckError,
  });

  final String currentVersion;
  final DesktopVersionInfo latest;
  final Future<void> Function() onRecheck;
  final bool rechecking;
  final String? recheckError;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;

  Future<void> _openDownload() async {
    if (_opening || widget.rechecking) return;
    setState(() => _opening = true);
    final url = widget.latest.preferredDownloadUrl();
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
                    'Update required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: MutandeColors.stone800,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'mutande $latest (${widget.latest.channel}) is available. '
                    'You’re on v$current — reinstall to keep using the alpha.',
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
                    label: 'Download update',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
