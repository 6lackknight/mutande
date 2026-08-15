import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import '../theme/mutande_macos_theme.dart';
import 'agents_screen.dart';
import 'contacts_screen.dart';

/// Directory tab: People (contacts) | Agents (routing graph). Read-only v1.
class NetworkPanel extends StatefulWidget {
  const NetworkPanel({
    super.key,
    required this.daemon,
    this.handle,
    this.inviteWebUrl,
    this.appVersion = '1.0.0',
    this.hostLinkStore,
    this.initialSegment = 0,
    this.onReloadPeople,
    this.onReloadAgents,
    this.onViewThreads,
    this.onStartThread,
  });

  final DaemonClient daemon;
  final String? handle;
  final String? inviteWebUrl;
  final String appVersion;
  final HostLinkStore? hostLinkStore;

  /// 0 People · 1 Agents.
  final int initialSegment;

  final void Function(VoidCallback? reload)? onReloadPeople;
  final void Function(VoidCallback? reload)? onReloadAgents;
  final VoidCallback? onViewThreads;
  final ValueChanged<String>? onStartThread;

  @override
  State<NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends State<NetworkPanel> {
  late int _segment;

  @override
  void initState() {
    super.initState();
    _segment = widget.initialSegment;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                _SegmentPill(
                  key: const Key('network-people'),
                  label: 'People',
                  selected: _segment == 0,
                  onTap: () => setState(() => _segment = 0),
                ),
                const SizedBox(width: 4),
                _SegmentPill(
                  key: const Key('network-agents'),
                  label: 'Agents',
                  selected: _segment == 1,
                  onTap: () => setState(() => _segment = 1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _segment == 0
                ? ContactsPanel(
                    daemon: widget.daemon,
                    handle: widget.handle,
                    inviteWebUrl:
                        widget.inviteWebUrl ?? AppConfig.defaultWebAppUrl,
                    onReloadReady: widget.onReloadPeople,
                    onStartThread: widget.onStartThread,
                  )
                : AgentsPanel(
                    daemon: widget.daemon,
                    handle: widget.handle,
                    appVersion: widget.appVersion,
                    hostLinkStore: widget.hostLinkStore,
                    onReloadReady: widget.onReloadAgents,
                    onViewThreads: widget.onViewThreads,
                    onStartThread: widget.onStartThread,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? MutandeColors.stone800 : MutandeColors.stone100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? MutandeColors.stone800 : MutandeColors.stone200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? MutandeColors.stone50 : MutandeColors.stone600,
          ),
        ),
      ),
    );
  }
}
