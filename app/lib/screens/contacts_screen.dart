import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../services/daemon_client.dart';
import '../util/address_display.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thinking_orb.dart';

/// Org address book — hub contacts, broadcast callout, copy handles.
class ContactsPanel extends StatefulWidget {
  const ContactsPanel({
    super.key,
    required this.daemon,
    this.handle,
    this.inviteWebUrl = AppConfig.defaultWebAppUrl,
    this.onReloadReady,
    this.onStartThread,
  });

  final DaemonClient daemon;
  final String? handle;
  final String inviteWebUrl;
  final void Function(VoidCallback? reload)? onReloadReady;
  final ValueChanged<String>? onStartThread;

  @override
  State<ContactsPanel> createState() => _ContactsPanelState();
}

class _ContactsPanelState extends State<ContactsPanel> {
  bool _loading = true;
  String? _error;
  List<ContactView> _contacts = const [];

  @override
  void initState() {
    super.initState();
    widget.onReloadReady?.call(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.onReloadReady?.call(null);
    super.dispose();
  }

  Future<void> _reload({bool soft = false}) async {
    if (!soft) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final contacts = await widget.daemon.listContacts();
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyContactsError(e);
        _loading = false;
      });
    }
  }

  ContactView? get _broadcast {
    for (final c in _contacts) {
      if (c.isBroadcast) return c;
    }
    return null;
  }

  List<ContactView> get _teammates =>
      _contacts.where((c) => !c.isBroadcast).toList();

  String? get _orgSlug {
    final h = widget.handle;
    if (h != null && h.contains('@')) return h.split('@').last;
    final b = _broadcast?.handle;
    if (b != null && b.startsWith('@all@')) return b.substring(5);
    return null;
  }

  void _copyHandle(String handle, {String? toast}) {
    Clipboard.setData(ClipboardData(text: handle));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(toast ?? 'Copied $handle'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openInvites() async {
    final url = '${widget.inviteWebUrl.replaceAll(RegExp(r'/+$'), '')}/admin/invites';
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
      return;
    }
    if (Platform.isWindows) {
      await Process.run('cmd', ['/C', 'start', '', url], runInShell: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied invite link: $url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: MutandeOrb.standard(semanticLabel: 'Loading contacts…'),
      );
    }

    if (_error != null) {
      return PaneQuietState(
        title: "Couldn't load contacts",
        body: _error!,
        onRetry: _reload,
        icon: Icons.cloud_off_outlined,
      );
    }

    final broadcast = _broadcast;
    final teammates = _teammates;
    final org = _orgSlug;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (widget.handle != null && widget.handle!.trim().isNotEmpty)
          _YourHandleCard(
            handle: widget.handle!,
            onCopy: () => _copyHandle(
              widget.handle!,
              toast: 'Copied your handle',
            ),
          ),
        if (broadcast != null) ...[
          const SizedBox(height: 12),
          _BroadcastCallout(
            handle: broadcast.handle,
            onCopy: () => _copyHandle(
              broadcast.handle,
              toast: 'Copied ${broadcast.handle}',
            ),
          ),
        ],
        if (teammates.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Teammates',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF78716C),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
            ),
          ),
          for (final contact in teammates)
            _TeammateRow(
              handle: contact.handle,
              onCopy: () => _copyHandle(contact.handle),
              onMessage: widget.onStartThread == null
                  ? null
                  : () => widget.onStartThread!(contact.handle),
            ),
        ] else if (org != null) ...[
          const SizedBox(height: 20),
          _SoloOrgBlock(
            orgSlug: org,
            onInvite: _openInvites,
          ),
        ],
      ],
    );
  }
}

String friendlyContactsError(Object error) {
  final base = friendlyDaemonError(error, what: 'Contacts');
  if (base.startsWith('Contacts took too long')) {
    return 'The hub took too long to load contacts. Try again.';
  }
  if (base.startsWith("Couldn't load Contacts")) {
    return "Couldn't load contacts from the hub. Check you're signed in, then retry.";
  }
  return base;
}

class _YourHandleCard extends StatelessWidget {
  const _YourHandleCard({required this.handle, required this.onCopy});

  final String handle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAFAF9),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your handle',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF78716C),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMailAddress(handle),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF292524),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 18),
                color: const Color(0xFF78716C),
                tooltip: 'Copy handle',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BroadcastCallout extends StatelessWidget {
  const _BroadcastCallout({required this.handle, required this.onCopy});

  final String handle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.campaign_outlined,
                  size: 20,
                  color: Color(0xFF92400E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMailAddress(handle),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF292524),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Broadcast to each member’s default agent',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF92400E),
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 18),
                color: const Color(0xFF92400E),
                tooltip: 'Copy broadcast handle',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeammateRow extends StatelessWidget {
  const _TeammateRow({
    required this.handle,
    required this.onCopy,
    this.onMessage,
  });

  final String handle;
  final VoidCallback onCopy;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final label = formatMailAddress(handle);
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCopy,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4))),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFF5F5F4),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFF57534E),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF292524),
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              if (onMessage != null)
                TextButton(
                  onPressed: onMessage,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Message'),
                ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 18),
                color: const Color(0xFF78716C),
                tooltip: 'Copy handle',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoloOrgBlock extends StatelessWidget {
  const _SoloOrgBlock({required this.orgSlug, required this.onInvite});

  final String orgSlug;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You’re the only member of $orgSlug',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF292524),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Invite teammates on the web. Once they join, broadcast reaches everyone’s default agent.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF78716C),
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onInvite,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF292524),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Invite teammates'),
          ),
        ],
      ),
    );
  }
}
