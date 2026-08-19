import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_transport.dart';
import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import 'ai_host_icon.dart';
import 'connect_host_picker.dart';
import 'onboarding_chrome.dart';
import 'thinking_orb.dart';

/// Walk through adding hosted MCP in ChatGPT Web or Claude.ai.
///
/// Returns true when a web agent for [spec.agentSlug] appears.
Future<bool?> showHostedMcpConnectFlow({
  required BuildContext context,
  required DaemonClient daemon,
  required AiHostSpec spec,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: MutandeColors.stone50,
        body: SafeArea(
          child: _HostedMcpFlow(daemon: daemon, spec: spec),
        ),
      ),
    ),
  );
}

class _HostedMcpFlow extends StatefulWidget {
  const _HostedMcpFlow({required this.daemon, required this.spec});

  final DaemonClient daemon;
  final AiHostSpec spec;

  @override
  State<_HostedMcpFlow> createState() => _HostedMcpFlowState();
}

class _HostedMcpFlowState extends State<_HostedMcpFlow> {
  bool _waiting = false;
  bool _cancelWait = false;
  String? _error;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _copyUrl() async {
    await Clipboard.setData(
      const ClipboardData(text: AiHostCatalog.hostedMcpUrl),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied connector URL'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _openHost() async {
    final url = widget.spec.openUrl;
    if (url == null) return;
    await Process.run('open', [url]);
  }

  Future<void> _startWait() async {
    setState(() {
      _waiting = true;
      _cancelWait = false;
      _error = null;
    });
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (mounted &&
        !_cancelWait &&
        DateTime.now().isBefore(deadline)) {
      try {
        final list = await widget.daemon.listAgents();
        final slug = widget.spec.agentSlug.toLowerCase();
        final found = list.agents.any(
          (a) =>
              a.slug.toLowerCase() == slug &&
              a.transport == AgentTransport.mcp,
        );
        if (found) {
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _error =
          'mutande hasn’t seen this web agent yet. Finish the connector, then Check again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final hostName = spec.id == 'claude-web' ? 'Claude.ai' : 'ChatGPT';

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AiHostIcon(spec.iconSlug, size: 28),
                    const SizedBox(width: OnboardingSpace.sm),
                    Flexible(
                      child: Text(
                        spec.label.toLowerCase(),
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
                  padding: const EdgeInsets.only(
                    left: 28 + OnboardingSpace.sm,
                  ),
                  child: Text(
                    _waiting
                        ? 'Waiting for the connector…'
                        : 'Step 1 of 1 — Connector',
                    style: const TextStyle(
                      color: MutandeColors.stone500,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
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
                  child: _waiting
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const MutandeOrb.standard(
                              semanticLabel: 'Waiting for connector…',
                            ),
                            const SizedBox(height: OnboardingSpace.lg),
                            OnboardingHeading(
                              variant: OnboardingHeadingVariant.display,
                              title: 'Finish the connector in $hostName.',
                              subtitle:
                                  'Sign in with the same Auth0 account, allow tools, then wait here.',
                            ),
                            OnboardingActions(
                              secondary: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _cancelWait = true;
                                    _waiting = false;
                                  });
                                },
                                child: const Text('Back'),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OnboardingHeading(
                              variant: OnboardingHeadingVariant.display,
                              title: 'Add mutande in $hostName.',
                              subtitle:
                                  'Browser mail isn’t end-to-end — the hub can read those threads.',
                            ),
                            const SizedBox(height: OnboardingSpace.lg),
                            Text(
                              '1. Open $hostName → Settings → Connectors (or MCP).\n'
                              '2. Add this remote MCP URL:\n'
                              '   ${AiHostCatalog.hostedMcpUrl}\n'
                              '3. Complete Auth0 login and allow mutande tools.',
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: MutandeColors.stone600,
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: OnboardingSpace.md),
                              OnboardingErrorBanner(message: _error!),
                            ],
                            OnboardingActions(
                              primary: FilledButton(
                                onPressed: _startWait,
                                child: const Text('I’ve added the connector'),
                              ),
                              secondary: TextButton(
                                onPressed: _copyUrl,
                                child: const Text('Copy URL'),
                              ),
                              tertiary: TextButton(
                                onPressed: spec.openUrl == null
                                    ? () => Navigator.of(context).pop()
                                    : _openHost,
                                child: spec.openUrl == null
                                    ? const Text('Cancel')
                                    : Text('Open $hostName'),
                              ),
                            ),
                            if (spec.openUrl != null)
                              OnboardingActions(
                                topSpacing: OnboardingSpace.sm,
                                secondary: TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
