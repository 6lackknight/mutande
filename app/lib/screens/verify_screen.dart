import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../widgets/thinking_orb.dart';

/// Minimal safety-number verify: show fingerprint + QR-payload stub, compare paste.
class VerifyContactPanel extends StatefulWidget {
  const VerifyContactPanel({super.key, required this.daemon});

  final DaemonClient daemon;

  @override
  State<VerifyContactPanel> createState() => _VerifyContactPanelState();
}

class _VerifyContactPanelState extends State<VerifyContactPanel> {
  final _handle = TextEditingController();
  final _compare = TextEditingController();
  SafetyNumberResult? _theirs;
  SafetyNumberResult? _ours;
  bool _loading = false;
  String? _error;
  bool? _verified;

  @override
  void initState() {
    super.initState();
    _loadOwn();
  }

  @override
  void dispose() {
    _handle.dispose();
    _compare.dispose();
    super.dispose();
  }

  Future<void> _loadOwn() async {
    try {
      final ours = await widget.daemon.getSafetyNumber();
      if (!mounted) return;
      setState(() => _ours = ours);
    } catch (_) {
      // optional
    }
  }

  Future<void> _lookup() async {
    final handle = _handle.text.trim();
    if (handle.isEmpty) {
      setState(() => _error = 'Handle is required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _verified = null;
      _theirs = null;
    });
    try {
      final result = await widget.daemon.contactSafetyNumber(handle);
      if (!mounted) return;
      setState(() {
        _theirs = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _verify() async {
    final handle = _handle.text.trim();
    final fp = _compare.text.trim();
    if (handle.isEmpty || fp.isEmpty) {
      setState(() => _error = 'Handle and fingerprint (or QR URI) required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.daemon.verifyContact(
        handle: handle,
        fingerprint: fp,
      );
      if (!mounted) return;
      setState(() {
        _theirs = result;
        _verified = result.verified;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify contact',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF292524),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Compare safety numbers out of band — serious, not playful.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF78716C),
          ),
        ),
        if (_ours != null) ...[
          const SizedBox(height: 12),
          Text(
            'Your number',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF78716C),
            ),
          ),
          SelectableText(
            _ours!.fingerprint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: const Color(0xFF292524),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _handle,
          decoration: const InputDecoration(
            labelText: 'Handle',
            hintText: 'alice@acme',
          ),
          enabled: !_loading,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _lookup,
                child: const Text('Show fingerprint'),
              ),
            ),
          ],
        ),
        if (_theirs != null) ...[
          const SizedBox(height: 16),
          Text(
            _theirs!.handle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          // QR stub: scannable payload rendered as a bordered block (host can
          // encode this string later; fingerprint compare works today).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE7E5E4)),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFFAFAF9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'QR payload',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA8A29E),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _theirs!.uri,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: const Color(0xFF44403C),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _theirs!.uri));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
                const Divider(height: 16),
                SelectableText(
                  _theirs!.fingerprint,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                    color: const Color(0xFF292524),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _compare,
          decoration: const InputDecoration(
            labelText: 'Their number or QR URI',
            hintText: 'Paste digits or mutande:safety:…',
          ),
          enabled: !_loading,
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _loading ? null : _verify,
          child: _loading
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MutandeOrb.loading(semanticLabel: 'Checking…'),
                    SizedBox(width: 8),
                    Text('Checking…'),
                  ],
                )
              : const Text('Compare'),
        ),
        if (_verified != null) ...[
          const SizedBox(height: 12),
          Text(
            _verified! ? 'Match — contact verified.' : 'No match — do not trust yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _verified! ? const Color(0xFF166534) : const Color(0xFF991B1B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF991B1B),
            ),
          ),
        ],
      ],
    );
  }
}
