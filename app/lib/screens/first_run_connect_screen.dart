import 'dart:async';

import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../services/first_run_store.dart';
import '../services/host_link_store.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/connect_host_picker.dart';
import '../widgets/thinking_orb.dart';

/// Blocking post-onboard step: connect one AI host, wait for agent registration.
class FirstRunConnectScreen extends StatefulWidget {
  const FirstRunConnectScreen({
    super.key,
    required this.daemon,
    required this.firstRunStore,
    required this.hostLinkStore,
    required this.onComplete,
  });

  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final HostLinkStore hostLinkStore;
  final VoidCallback onComplete;

  @override
  State<FirstRunConnectScreen> createState() => _FirstRunConnectScreenState();
}

class _FirstRunConnectScreenState extends State<FirstRunConnectScreen> {
  bool _connecting = false;
  bool _waiting = false;
  String? _host;
  String? _error;
  String? _hint;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pickAndConnect() async {
    final links = await widget.hostLinkStore.load();
    if (!mounted) return;
    final host = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ConnectHostPicker(
        title: 'Connect an AI host',
        subtitle: 'Pick one host to link MCP. You can add more later in Settings.',
        hostLinks: links,
      ),
    );
    if (host == null || !mounted) return;
    await _connect(host);
  }

  Future<void> _connect(String host) async {
    setState(() {
      _connecting = true;
      _waiting = false;
      _host = host;
      _error = null;
      _hint = null;
    });
    try {
      final result = await widget.daemon.connectHost(host);
      for (final write in result.hosts) {
        await widget.hostLinkStore.record(write);
      }
      final ok = result.hosts.any((h) => h.ok);
      if (!ok) {
        if (!mounted) return;
        final notes = result.hosts
            .map((h) => h.note)
            .whereType<String>()
            .where((n) => n.isNotEmpty)
            .toList();
        setState(() {
          _connecting = false;
          _error = notes.isNotEmpty
              ? notes.first
              : 'Could not write MCP config.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _waiting = true;
        _hint = _restartHint(host);
      });
      await _waitForRegistration(host);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _waiting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _waitForRegistration(String host) async {
    _poll?.cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    final completer = Completer<bool>();

    Future<void> tick() async {
      try {
        final agents = await widget.daemon.listAgents();
        final found = agents.agents.any(
          (a) => a.slug.toLowerCase() == host.toLowerCase(),
        );
        if (found) {
          if (!completer.isCompleted) completer.complete(true);
          return;
        }
      } catch (_) {
        // Keep polling through transient daemon blips.
      }
      if (DateTime.now().isAfter(deadline)) {
        if (!completer.isCompleted) completer.complete(false);
      }
    }

    await tick();
    if (!completer.isCompleted) {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => tick());
    }
    final ok = await completer.future;
    _poll?.cancel();
    if (!mounted) return;
    if (ok) {
      await widget.firstRunStore.markConnectComplete();
      widget.onComplete();
      return;
    }
    setState(() {
      _waiting = false;
      _error =
          'Host config written, but mutande hasn’t seen the agent yet. Restart the host, then Retry.';
      _hint = _restartHint(host);
    });
  }

  Future<void> _finishWithoutWait() async {
    await widget.firstRunStore.markConnectComplete();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Connect an AI host',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF292524),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'mutande talks to your agents over MCP. Connect one host to send your first ping.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF78716C),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_connecting || _waiting) ...[
                    const Center(
                      child: MutandeOrb.standard(semanticLabel: 'Connecting…'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _waiting
                          ? 'Waiting for ${_hostDisplay(_host)} to register…'
                          : 'Writing MCP config…',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF57534E),
                      ),
                    ),
                    if (_hint != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _hint!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFA8A29E),
                        ),
                      ),
                    ],
                  ] else ...[
                    if (_host != null) ...[
                      Center(child: AiHostIcon(_host!, size: 48)),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: _pickAndConnect,
                      child: Text(
                        _host == null ? 'Choose host' : 'Choose a different host',
                      ),
                    ),
                    if (_host != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => _connect(_host!),
                        child: const Text('Retry'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _finishWithoutWait,
                        child: const Text('Continue anyway'),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF991B1B),
                      ),
                    ),
                    if (_hint != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _hint!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF78716C),
                        ),
                      ),
                    ],
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

String _hostDisplay(String? host) {
  switch ((host ?? '').toLowerCase()) {
    case 'cursor':
      return 'Cursor';
    case 'claude':
      return 'Claude Desktop';
    case 'chatgpt':
      return 'ChatGPT';
    default:
      return host ?? 'host';
  }
}

String _restartHint(String host) {
  switch (host.toLowerCase()) {
    case 'cursor':
      return 'Restart Cursor (or reload MCP) so it picks up the mutande server.';
    case 'claude':
      return 'Quit and reopen Claude Desktop so it loads the new MCP config.';
    case 'chatgpt':
      return 'Open ChatGPT → Settings → MCP. If the config path looks wrong, check docs.';
    default:
      return 'Restart the host so it loads the mutande MCP server.';
  }
}
