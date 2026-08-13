import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_config.dart';
import '../services/daemon_client.dart';
import '../util/address_display.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thinking_orb.dart';

/// Org address book — hub contacts, broadcast, external pairing.
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
  List<ContactView> _external = const [];
  List<PairRequestView> _incoming = const [];
  List<PairRequestView> _outgoing = const [];
  bool _busy = false;

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
      List<ContactView> external = const [];
      List<PairRequestView> incoming = const [];
      List<PairRequestView> outgoing = const [];
      try {
        external = await widget.daemon.listExternalContacts();
        final pending = await widget.daemon.listPendingPairRequests();
        incoming = pending.incoming;
        outgoing = pending.outgoing;
      } catch (_) {
        // External APIs may be unreachable on older daemons — org contacts still show.
      }
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _external = external;
        _incoming = incoming;
        _outgoing = outgoing;
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
      // Avoid `cmd /C start` — `&` in URLs is a cmd command separator.
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied invite link: $url')),
    );
  }

  Future<void> _showSharePin() async {
    setState(() => _busy = true);
    try {
      var pin = await widget.daemon.getPairingPin();
      pin ??= await widget.daemon.issuePairingPin();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => _PairPinDialog(
          pin: pin!,
          onRotate: () async {
            final next = await widget.daemon.rotatePairingPin();
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (c2) => _PairPinDialog(pin: next, onRotate: null),
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Pairing PIN'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRequestPair() async {
    final result = await showDialog<(String, String, String?)>(
      context: context,
      builder: (ctx) => const _RequestPairDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.daemon.submitPairRequest(
        handle: result.$1,
        pin: result.$2,
        intro: result.$3,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pairing request sent — waiting for approval')),
      );
      await _reload(soft: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Pairing'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(PairRequestView req) async {
    setState(() => _busy = true);
    try {
      await widget.daemon.approvePairRequest(req.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected with ${req.requesterHandle}')),
      );
      await _reload(soft: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Approve'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deny(PairRequestView req) async {
    setState(() => _busy = true);
    try {
      await widget.daemon.denyPairRequest(req.id);
      if (!mounted) return;
      await _reload(soft: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Deny'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unpair(ContactView c) async {
    final linkId = c.externalLinkId;
    if (linkId == null || linkId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove external contact?'),
        content: Text(
          'Unpair ${formatMailAddress(c.handle)}? Shared threads close (read-only).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.daemon.unpairExternalContact(linkId);
      if (!mounted) return;
      await _reload(soft: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Unpair'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              name: contact.displayName,
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
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'External',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF78716C),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _showSharePin,
                child: const Text('Share PIN'),
              ),
              TextButton(
                onPressed: _busy ? null : _showRequestPair,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        Text(
          'Cross-org contacts via exact handle + PIN. Mail is not E2E (app envelope).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFA8A29E),
                height: 1.35,
              ),
        ),
        if (_incoming.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final req in _incoming)
            _PendingPairRow(
              title: formatMailAddress(req.requesterHandle),
              subtitle: req.intro?.trim().isNotEmpty == true
                  ? req.intro!
                  : 'Wants to connect',
              onApprove: _busy ? null : () => _approve(req),
              onDeny: _busy ? null : () => _deny(req),
            ),
        ],
        if (_outgoing.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final req in _outgoing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Pending → ${formatMailAddress(req.targetHandle)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF78716C),
                    ),
              ),
            ),
        ],
        if (_external.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final contact in _external)
            _ExternalRow(
              handle: contact.handle,
              name: contact.displayName,
              onCopy: () => _copyHandle(contact.handle),
              onMessage: widget.onStartThread == null
                  ? null
                  : () => widget.onStartThread!(contact.handle),
              onRemove: _busy ? null : () => _unpair(contact),
            ),
        ] else if (_incoming.isEmpty && _outgoing.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'No external contacts yet. Share your PIN or add someone else’s handle + PIN.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFA8A29E),
                  height: 1.4,
                ),
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
    this.name,
    this.onMessage,
  });

  final String handle;
  final String? name;
  final VoidCallback onCopy;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final display = name?.trim();
    final titled = display != null && display.isNotEmpty;
    final label = titled ? display : formatMailAddress(handle);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF292524),
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (titled)
                      Text(
                        formatMailAddress(handle),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFA8A29E),
                            ),
                      ),
                  ],
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

class _ExternalRow extends StatelessWidget {
  const _ExternalRow({
    required this.handle,
    required this.onCopy,
    this.name,
    this.onMessage,
    this.onRemove,
  });

  final String handle;
  final String? name;
  final VoidCallback onCopy;
  final VoidCallback? onMessage;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final display = name?.trim();
    final titled = display != null && display.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4))),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, size: 18, color: Color(0xFF78716C)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titled ? display : formatMailAddress(handle),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF292524),
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Text(
                  titled
                      ? formatMailAddress(handle)
                      : 'via external · not E2E',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFA8A29E),
                      ),
                ),
              ],
            ),
          ),
          if (onMessage != null)
            TextButton(onPressed: onMessage, child: const Text('Message')),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 18),
            color: const Color(0xFF78716C),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.link_off, size: 18),
              color: const Color(0xFF991B1B),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}

class _PendingPairRow extends StatelessWidget {
  const _PendingPairRow({
    required this.title,
    required this.subtitle,
    this.onApprove,
    this.onDeny,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF292524),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF78716C)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF292524),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Approve'),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onDeny, child: const Text('Deny')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PairPinDialog extends StatelessWidget {
  const _PairPinDialog({required this.pin, this.onRotate});

  final PairingPinView pin;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair external contact'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your PIN for ${formatMailAddress(pin.handle)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF78716C)),
            ),
            const SizedBox(height: 12),
            Text(
              pin.pin,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: Color(0xFF1C1917),
              ),
            ),
            const SizedBox(height: 16),
            QrImageView(
              data: pin.qrUri,
              size: 180,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            SelectableText(
              pin.qrUri,
              style: const TextStyle(fontSize: 11, color: Color(0xFFA8A29E)),
            ),
            const SizedBox(height: 4),
            Text(
              'Expires ${pin.expiresAt.isEmpty ? "in 7 days" : pin.expiresAt}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA8A29E)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: pin.qrUri));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied pair URI')),
            );
          },
          child: const Text('Copy URI'),
        ),
        if (onRotate != null)
          TextButton(onPressed: onRotate, child: const Text('Rotate PIN')),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _RequestPairDialog extends StatefulWidget {
  const _RequestPairDialog();

  @override
  State<_RequestPairDialog> createState() => _RequestPairDialogState();
}

class _RequestPairDialogState extends State<_RequestPairDialog> {
  final _handle = TextEditingController();
  final _pin = TextEditingController();
  final _intro = TextEditingController();

  @override
  void dispose() {
    _handle.dispose();
    _pin.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add external contact'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _handle,
              decoration: const InputDecoration(
                labelText: 'Exact handle',
                hintText: 'alice@aliceco',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pin,
              decoration: const InputDecoration(
                labelText: '6-digit PIN',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            TextField(
              controller: _intro,
              decoration: const InputDecoration(
                labelText: 'Intro (optional)',
              ),
              maxLength: 200,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final h = _handle.text.trim();
            final p = _pin.text.trim();
            if (h.isEmpty || p.length != 6) return;
            final intro = _intro.text.trim();
            Navigator.pop(context, (h, p, intro.isEmpty ? null : intro));
          },
          child: const Text('Send request'),
        ),
      ],
    );
  }
}
