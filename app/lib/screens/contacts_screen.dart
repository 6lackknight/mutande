import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_config.dart';
import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../widgets/collab/collab_dash_card.dart';
import '../widgets/mutande_stagger.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/person_identity_row.dart';
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

  ContactView? get _selfContact {
    final mine = widget.handle?.trim().toLowerCase();
    if (mine == null || mine.isEmpty) return null;
    for (final c in _contacts) {
      if (c.handle.toLowerCase() == mine) return c;
    }
    return null;
  }

  List<ContactView> get _teammates {
    final mine = widget.handle?.trim().toLowerCase();
    return _contacts.where((c) {
      if (c.isBroadcast || c.isExternal) return false;
      if (mine != null && mine.isNotEmpty && c.handle.toLowerCase() == mine) {
        return false;
      }
      return true;
    }).toList();
  }

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
    final url =
        '${widget.inviteWebUrl.replaceAll(RegExp(r'/+$'), '')}/admin/invites';
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied invite link: $url')));
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
        const SnackBar(
          content: Text('Pairing request sent — waiting for approval'),
        ),
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

    return MutandeStaggerScope(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _DashListCard(
            title: 'People',
            children: [
              if (widget.handle != null && widget.handle!.trim().isNotEmpty)
                MutandeStaggerIn(
                  id: 'self',
                  child: PersonIdentityRow(
                    title: personDisplayTitle(
                      displayName: _selfContact?.displayName,
                      handle: widget.handle!,
                    ),
                    handle: widget.handle!,
                    avatarUrl: _selfContact?.avatarUrl,
                    badge: PersonIdentityRow.statusPill(label: 'you'),
                    isSelf: true,
                    onTap: () => _copyHandle(
                      widget.handle!,
                      toast: 'Copied your handle',
                    ),
                    trailing: [
                      _CopyIcon(
                        onPressed: () => _copyHandle(
                          widget.handle!,
                          toast: 'Copied your handle',
                        ),
                      ),
                    ],
                    showDivider: teammates.isNotEmpty || org != null,
                  ),
                ),
              for (var i = 0; i < teammates.length; i++)
                MutandeStaggerIn(
                  id: teammates[i].handle,
                  child: PersonIdentityRow(
                    title: personDisplayTitle(
                      displayName: teammates[i].displayName,
                      handle: teammates[i].handle,
                    ),
                    handle: teammates[i].handle,
                    avatarUrl: teammates[i].avatarUrl,
                    onTap: () => _copyHandle(teammates[i].handle),
                    trailing: [
                      if (widget.onStartThread != null)
                        _QuietTextAction(
                          label: 'Message',
                          onPressed: () =>
                              widget.onStartThread!(teammates[i].handle),
                        ),
                      _CopyIcon(
                        onPressed: () => _copyHandle(teammates[i].handle),
                      ),
                    ],
                    showDivider: i < teammates.length - 1,
                  ),
                ),
              if (teammates.isEmpty && org != null)
                _SoloInviteBody(orgSlug: org, onInvite: _openInvites),
            ],
          ),
          if (broadcast != null) ...[
            const SizedBox(height: 12),
            _DashListCard(
              title: 'Broadcast',
              children: [
                PersonIdentityRow(
                  title: formatMailAddress(broadcast.handle),
                  handle: broadcast.handle,
                  subtitle: 'Broadcast to each member’s default agent',
                  leading: const _MarkIcon(Icons.campaign_outlined),
                  onTap: () => _copyHandle(
                    broadcast.handle,
                    toast: 'Copied ${broadcast.handle}',
                  ),
                  trailing: [
                    _CopyIcon(
                      onPressed: () => _copyHandle(
                        broadcast.handle,
                        toast: 'Copied ${broadcast.handle}',
                      ),
                      tooltip: 'Copy broadcast handle',
                    ),
                  ],
                  showDivider: false,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _DashListCard(
            title: 'External',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QuietTextAction(
                  label: 'Share PIN',
                  onPressed: _busy ? null : _showSharePin,
                ),
                _QuietTextAction(
                  label: 'Add',
                  onPressed: _busy ? null : _showRequestPair,
                ),
              ],
            ),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Cross-org contacts via exact handle + PIN. Mail is not E2E (app envelope).',
                  style: TextStyle(
                    fontSize: 11,
                    color: MutandeColors.stone400,
                    height: 1.35,
                  ),
                ),
              ),
              if (_incoming.isNotEmpty)
                for (final req in _incoming)
                  _PendingPairRow(
                    title: formatMailAddress(req.requesterHandle),
                    subtitle: req.intro?.trim().isNotEmpty == true
                        ? req.intro!
                        : 'Wants to connect',
                    onApprove: _busy ? null : () => _approve(req),
                    onDeny: _busy ? null : () => _deny(req),
                  ),
              if (_outgoing.isNotEmpty)
                for (final req in _outgoing)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Pending → ${formatMailAddress(req.targetHandle)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: MutandeColors.stone500,
                      ),
                    ),
                  ),
              if (_external.isNotEmpty)
                for (var i = 0; i < _external.length; i++)
                  PersonIdentityRow(
                    title: personDisplayTitle(
                      displayName: _external[i].displayName,
                      handle: _external[i].handle,
                    ),
                    handle: _external[i].handle,
                    subtitle:
                        _external[i].displayName?.trim().isNotEmpty == true
                        ? null
                        : 'via external · not E2E',
                    avatarUrl: _external[i].avatarUrl,
                    leading: _external[i].avatarUrl == null
                        ? const _MarkIcon(Icons.link)
                        : null,
                    onTap: () => _copyHandle(_external[i].handle),
                    trailing: [
                      if (widget.onStartThread != null)
                        _QuietTextAction(
                          label: 'Message',
                          onPressed: () =>
                              widget.onStartThread!(_external[i].handle),
                        ),
                      _CopyIcon(
                        onPressed: () => _copyHandle(_external[i].handle),
                      ),
                      if (!_busy)
                        IconButton(
                          onPressed: () => _unpair(_external[i]),
                          icon: const Icon(Icons.link_off, size: 18),
                          color: const Color(0xFF991B1B),
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                    ],
                    showDivider: i < _external.length - 1,
                  )
              else if (_incoming.isEmpty && _outgoing.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No external contacts yet. Share your PIN or add someone else’s handle + PIN.',
                    style: TextStyle(
                      fontSize: 12,
                      color: MutandeColors.stone400,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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

class _DashListCard extends StatelessWidget {
  const _DashListCard({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CollabDashCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MutandeColors.stone800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _CopyIcon extends StatelessWidget {
  const _CopyIcon({required this.onPressed, this.tooltip = 'Copy handle'});

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.copy, size: 18),
      color: MutandeColors.stone600,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}

class _QuietTextAction extends StatelessWidget {
  const _QuietTextAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: MutandeColors.stone800,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(44, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _MarkIcon extends StatelessWidget {
  const _MarkIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: PersonIdentityRow.avatarSize,
      height: PersonIdentityRow.avatarSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: MutandeColors.stone100,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: MutandeColors.stone600),
      ),
    );
  }
}

class _SoloInviteBody extends StatelessWidget {
  const _SoloInviteBody({required this.orgSlug, required this.onInvite});

  final String orgSlug;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You’re the only member of $orgSlug',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Invite teammates on the web. Once they join, broadcast reaches everyone’s default agent.',
            style: TextStyle(
              fontSize: 12,
              color: MutandeColors.stone500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onInvite,
            style: FilledButton.styleFrom(
              backgroundColor: MutandeColors.stone800,
              foregroundColor: MutandeColors.stone50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Invite teammates'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: MutandeColors.stone500),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: MutandeColors.stone800,
                  foregroundColor: MutandeColors.stone50,
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Copied pair URI')));
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
              decoration: const InputDecoration(labelText: '6-digit PIN'),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            TextField(
              controller: _intro,
              decoration: const InputDecoration(labelText: 'Intro (optional)'),
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
