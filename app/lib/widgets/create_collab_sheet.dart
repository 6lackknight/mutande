import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../models/agent_transport.dart';
import '../services/daemon_client.dart';
import '../services/daemon_errors.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import 'ai_host_icon.dart';
import 'contact_avatar.dart';
import 'thinking_orb.dart';
import 'transport_chip.dart';

/// Honest encryption copy — never says "insecure"; names the cause address.
String collabEncryptionCopy({
  required bool e2e,
  String? causeAddress,
  bool external = false,
}) {
  if (e2e) {
    return 'Mail in this collab is sealed to steerer devices.';
  }
  final who = (causeAddress ?? (external ? 'this contact' : 'a hosted agent'))
      .toLowerCase();
  if (external) {
    return "E2E isn't available for this collab — $who is outside the org — mail goes through the hub.";
  }
  return "E2E isn't available for this collab — $who reads mail through the hub.";
}

/// Bare human handle (`alice@acme`). Drops agent suffix and `/default`.
String? bareCollabHandle(String? raw) {
  if (raw == null) return null;
  var h = raw.trim().toLowerCase();
  if (h.isEmpty) return null;
  if (h.endsWith('/default')) {
    h = h.substring(0, h.length - '/default'.length);
  }
  final slash = h.indexOf('/');
  if (slash >= 0) h = h.substring(0, slash);
  if (h.startsWith('@all@')) return null;
  if (!h.contains('@') || h.startsWith('@')) return null;
  return h;
}

/// Roster slug for chips — empty and `default` are not shown.
String? collabRosterSlug(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  if (s.isEmpty || s == 'default') return null;
  return s;
}

/// Full cause address (`alice@acme/chatgpt`) — never `/default` or `@slug`.
String collabCauseAddress({required String ownerHandle, required String slug}) {
  final owner = bareCollabHandle(ownerHandle) ?? ownerHandle.trim().toLowerCase();
  final agent = collabRosterSlug(slug) ?? slug.trim().toLowerCase();
  return '$owner/$agent';
}

/// Participants = steerers ∪ roster. Me + one agent is 2; solo me is 1.
int collabParticipantCount({
  required Iterable<String> steerers,
  required Iterable<String> roster,
}) {
  final ids = <String>{};
  void add(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isNotEmpty) ids.add(t);
  }

  for (final s in steerers) {
    add(s);
  }
  for (final r in roster) {
    add(r);
  }
  return ids.length;
}

/// Instructions stay optional to fill; always visible when participant count > 1.
bool collabInstructionsVisible({
  required Iterable<String> steerers,
  required Iterable<String> roster,
}) =>
    collabParticipantCount(steerers: steerers, roster: roster) > 1;

({bool e2e, String? causeAddress, bool external}) collabRosterEncryption(
  Iterable<({String causeAddress, AgentTransport? transport})> selected, {
  Iterable<String> externalHandles = const [],
}) {
  for (final raw in externalHandles) {
    final handle = bareCollabHandle(raw) ?? raw.trim().toLowerCase();
    if (handle.isEmpty) continue;
    return (e2e: false, causeAddress: handle, external: true);
  }
  for (final a in selected) {
    if (isHostedWebTransport(a.transport)) {
      return (
        e2e: false,
        causeAddress: a.causeAddress.toLowerCase(),
        external: false,
      );
    }
  }
  return (e2e: true, causeAddress: null, external: false);
}

/// Local-part of `alice@acme` → `alice`.
String collabHandleLocalPart(String handle) {
  final h = (bareCollabHandle(handle) ?? handle.trim()).toLowerCase();
  return handleLocalPart(h);
}

/// Title line: display name, else handle local-part.
String collabPersonTitle({String? displayName, required String handle}) =>
    personDisplayTitle(displayName: displayName, handle: handle);

/// Initials from a display name (`Tawanda Brandon` → `TB`) or local-part (`tawanda` → `TA`).
String collabPersonInitials(String title) => personInitials(title);

/// One picker row per agent_id; same owner+slug sidecar+web → one web chip.
List<CollabPickerAgent> collapseCollabAgents(Iterable<CollabPickerAgent> raw) {
  final byId = <String, CollabPickerAgent>{};
  final rest = <CollabPickerAgent>[];
  for (final a in raw) {
    final id = a.agentId.trim();
    if (id.isEmpty) {
      rest.add(a);
      continue;
    }
    final prev = byId[id];
    byId[id] = prev == null ? a : _mergeCollabAgent(prev, a);
  }
  final byKey = <String, CollabPickerAgent>{};
  for (final a in [...byId.values, ...rest]) {
    final key = '${a.ownerHandle}\u0000${a.slug}';
    final prev = byKey[key];
    byKey[key] = prev == null ? a : _mergeCollabAgent(prev, a);
  }
  return byKey.values.toList();
}

CollabPickerAgent _mergeCollabAgent(CollabPickerAgent a, CollabPickerAgent b) {
  final web = isHostedWebTransport(a.transport) ||
          isHostedWebTransport(b.transport)
      ? AgentTransport.mcp
      : (a.transport ?? b.transport);
  final aShort = a.address.startsWith('@');
  final bShort = b.address.startsWith('@');
  final keep = aShort && !bShort ? a : (!aShort && bShort ? b : a);
  return CollabPickerAgent(
    agentId: keep.agentId.isNotEmpty ? keep.agentId : b.agentId,
    address: keep.address,
    ownerHandle: keep.ownerHandle,
    slug: keep.slug,
    causeAddress: keep.causeAddress,
    transport: web,
  );
}

Future<CollabDetail?> showCreateCollabSheet({
  required BuildContext context,
  required DaemonClient daemon,
  String? handle,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = size.width.clamp(360.0, 480.0);
  final height = (size.height - 72).clamp(400.0, 560.0);
  return showMacosSheet<CollabDetail>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => MacosSheet(
      child: SizedBox(
        width: width,
        height: height,
        child: CreateCollabSheet(daemon: daemon, handle: handle),
      ),
    ),
  );
}

/// Create-collab form — people + agent chip pickers, roster ⊆ steerers.
class CreateCollabSheet extends StatefulWidget {
  const CreateCollabSheet({super.key, required this.daemon, this.handle});

  final DaemonClient daemon;
  final String? handle;

  @override
  State<CreateCollabSheet> createState() => _CreateCollabSheetState();
}

class _PersonOpt {
  const _PersonOpt({
    required this.handle,
    this.listHandle,
    this.displayName,
    this.avatarUrl,
    this.isSelf = false,
    this.isExternal = false,
  });

  /// Lowercase identity (`alice@acme`).
  final String handle;

  /// Hub casing for `list_agents?handle=` — prod 404s on a lowercased handle.
  final String? listHandle;
  final String? displayName;
  final String? avatarUrl;
  final bool isSelf;
  final bool isExternal;

  String get rpcHandle {
    final raw = listHandle?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return handle;
  }
}

class CollabPickerAgent {
  const CollabPickerAgent({
    required this.address,
    required this.ownerHandle,
    required this.slug,
    required this.causeAddress,
    this.agentId = '',
    this.transport,
  });

  final String agentId;
  final String address;
  final String ownerHandle;
  final String slug;
  final String causeAddress;
  final AgentTransport? transport;
}

class _CreateCollabSheetState extends State<CreateCollabSheet> {
  final _name = TextEditingController();
  final _instructions = TextEditingController();
  bool _busy = false;
  bool _loading = true;
  String? _error;
  String? _pickerError;
  bool _needsSignIn = false;
  String? _cause;
  bool _e2e = true;
  bool _externalCause = false;

  List<_PersonOpt> _people = const [];
  List<CollabPickerAgent> _agents = const [];
  final _steerers = <String>{};
  final _roster = <String>{};

  String? get _me => bareCollabHandle(widget.handle);

  bool get _showInstructions => collabInstructionsVisible(
        steerers: _steerers,
        roster: _roster,
      );

  @override
  void initState() {
    super.initState();
    _loadPickers();
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<(AgentListResult, Object?)> _agentsFor({String? handle}) async {
    try {
      return (await widget.daemon.listAgents(handle: handle), null);
    } catch (e) {
      return (const AgentListResult(agents: []), e);
    }
  }

  String _loadErrorCopy(Object e, {required String what}) {
    final lower = e.toString().toLowerCase();
    if (isHubAuthFailure(lower)) {
      return friendlyDaemonError(e, what: what);
    }
    if (isHubUnimplemented(lower) ||
        lower.contains('404') ||
        lower.contains('not found')) {
      return "Couldn't load $what. Retry.";
    }
    return friendlyDaemonError(e, what: what);
  }

  Future<void> _loadPickers() async {
    final keepForm =
        !_loading || _people.isNotEmpty || _name.text.trim().isNotEmpty;
    setState(() {
      if (!keepForm) _loading = true;
      _pickerError = null;
      _needsSignIn = false;
    });
    Object? contactsErr;
    Object? ownAgentsErr;
    try {
      List<ContactView> contacts = const [];
      try {
        contacts = await widget.daemon.listContacts();
      } catch (e) {
        contactsErr = e;
      }
      // Alpha lists approved externals in this same People row
      // (docs/COLLAB-PRD.md). Using them in a collab is ungated for now;
      // a paid/feature gate comes later. Pair first in Contacts — do not
      // add a pairing flow here.
      List<ContactView> external = const [];
      try {
        external = await widget.daemon.listExternalContacts();
      } catch (_) {
        // Older daemons / hub — org members still show.
      }

      final me = _me;
      String? selfName;
      String? selfAvatar;
      String? selfListHandle = widget.handle?.trim();
      final people = <_PersonOpt>[];
      final seen = <String>{};
      for (final c in contacts) {
        if (c.isBroadcast) continue;
        final h = bareCollabHandle(c.handle);
        if (h == null) continue;
        if (h == me) {
          selfName = c.displayName;
          selfAvatar = c.avatarUrl;
          selfListHandle = c.handle.trim();
          continue;
        }
        seen.add(h);
        people.add(_PersonOpt(
          handle: h,
          listHandle: c.handle.trim(),
          displayName: c.displayName,
          avatarUrl: c.avatarUrl,
          isExternal: c.isExternal,
        ));
      }
      for (final c in external) {
        if (c.isBroadcast) continue;
        final h = bareCollabHandle(c.handle);
        if (h == null || h == me || seen.contains(h)) continue;
        seen.add(h);
        people.add(_PersonOpt(
          handle: h,
          listHandle: c.handle.trim(),
          displayName: c.displayName,
          avatarUrl: c.avatarUrl,
          isExternal: true,
        ));
      }
      if (me != null) {
        people.insert(
          0,
          _PersonOpt(
            handle: me,
            listHandle: selfListHandle,
            displayName: selfName,
            avatarUrl: selfAvatar,
            isSelf: true,
          ),
        );
      }

      final agents = <CollabPickerAgent>[];
      if (me != null) {
        final (own, err) = await _agentsFor();
        ownAgentsErr = err;
        for (final a in own.agents) {
          final opt = _ownAgent(me, a);
          if (opt != null) agents.add(opt);
        }
      }

      final others = people.where((p) => !p.isSelf).toList();
      final teammateLists = await Future.wait(
        others.map((p) async {
          final (list, _) = await _agentsFor(handle: p.rpcHandle);
          return (p.handle, list);
        }),
      );
      for (final (handle, list) in teammateLists) {
        for (final a in list.agents) {
          final opt = _teammateAgent(handle, a);
          if (opt != null) agents.add(opt);
        }
      }

      if (!mounted) return;
      final contactsFailed = contactsErr != null;
      final onlySelf = people.length <= (me == null ? 0 : 1);
      String? pickerError;
      var needsSignIn = false;
      if (contactsFailed && onlySelf) {
        pickerError = _loadErrorCopy(contactsErr, what: 'people');
        needsSignIn = isHubAuthFailure(contactsErr.toString().toLowerCase());
      } else if (ownAgentsErr != null && agents.isEmpty) {
        pickerError = _loadErrorCopy(ownAgentsErr, what: 'agents');
        needsSignIn = isHubAuthFailure(ownAgentsErr.toString().toLowerCase());
      }
      setState(() {
        _people = people;
        _agents = collapseCollabAgents(agents);
        if (me != null) _steerers.add(me);
        _loading = false;
        _pickerError = pickerError;
        _needsSignIn = needsSignIn;
        _syncEncryption();
      });
    } catch (e) {
      if (!mounted) return;
      final lower = e.toString().toLowerCase();
      setState(() {
        _loading = false;
        _pickerError = _loadErrorCopy(e, what: 'people');
        _needsSignIn = isHubAuthFailure(lower);
      });
    }
  }

  CollabPickerAgent? _ownAgent(String owner, AgentInfo a) {
    final slug = collabRosterSlug(a.slug);
    if (slug == null) return null;
    return CollabPickerAgent(
      agentId: a.id,
      address: '@$slug',
      ownerHandle: owner,
      slug: slug,
      causeAddress: collabCauseAddress(ownerHandle: owner, slug: slug),
      transport: a.transport,
    );
  }

  CollabPickerAgent? _teammateAgent(String owner, AgentInfo a) {
    final slug = collabRosterSlug(a.slug);
    if (slug == null) return null;
    final handle = owner.toLowerCase();
    return CollabPickerAgent(
      agentId: a.id,
      address: '$handle/$slug',
      ownerHandle: handle,
      slug: slug,
      causeAddress: collabCauseAddress(ownerHandle: handle, slug: slug),
      transport: a.transport,
    );
  }

  void _syncEncryption() {
    final selected = _agents.where((a) => _roster.contains(a.address)).map(
      (a) => (causeAddress: a.causeAddress, transport: a.transport),
    );
    final next = collabRosterEncryption(
      selected,
      externalHandles: _people
          .where((p) => p.isExternal && _steerers.contains(p.handle))
          .map((p) => p.handle),
    );
    _e2e = next.e2e;
    _cause = next.causeAddress;
    _externalCause = next.external;
  }

  void _togglePerson(_PersonOpt p) {
    if (_busy || p.isSelf) return;
    setState(() {
      if (_steerers.contains(p.handle)) {
        _steerers.remove(p.handle);
        _roster.removeWhere((addr) {
          for (final a in _agents) {
            if (a.address == addr && a.ownerHandle == p.handle) return true;
          }
          return false;
        });
      } else {
        _steerers.add(p.handle);
      }
      _error = null;
      _syncEncryption();
    });
  }

  void _toggleAgent(CollabPickerAgent a) {
    if (_busy) return;
    setState(() {
      if (_roster.contains(a.address)) {
        _roster.remove(a.address);
      } else {
        _roster.add(a.address);
        _steerers.add(a.ownerHandle);
      }
      _error = null;
      _syncEncryption();
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name this collab.');
      return;
    }
    if (_roster.isEmpty) {
      setState(() => _error = 'Pick at least one agent.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _needsSignIn = false;
    });
    try {
      final instructions = _instructions.text.trim();
      final created = await widget.daemon.createCollab(
        name: name,
        steererHandles: _steerers.toList(),
        rosterAddresses: _roster.map((a) => a.toLowerCase()).toList(),
        instructions: _e2e || instructions.isEmpty ? null : instructions,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      final lower = e.toString().toLowerCase();
      setState(() {
        _busy = false;
        _needsSignIn = isHubAuthFailure(lower);
        if (isHubUnimplemented(lower)) {
          _error = "This hub doesn't support collab yet.";
        } else {
          _error = friendlyDaemonError(e, what: 'Create collab');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MutandeColors.stone50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Create collab',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: MutandeColors.stone800,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? Center(
                      child: MutandeOrb.standard(size: ThinkingOrbSize.panel),
                    )
                  : ListView(
                      children: [
                        const _SectionLabel('Name'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _name,
                          autofocus: true,
                          enabled: !_busy,
                          maxLength: 120,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          decoration: const InputDecoration(
                            hintText: 'e.g. launch week',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 20),
                        const _SectionLabel('People'),
                        const SizedBox(height: 8),
                        _ChipPane(
                          empty: _people.isEmpty
                              ? 'No people yet.'
                              : null,
                          maxHeight: 168,
                          children: [
                            for (final p in _people)
                              _PersonChip(
                                title: collabPersonTitle(
                                  displayName: p.displayName,
                                  handle: p.handle,
                                ),
                                handle: formatMailAddress(p.handle),
                                avatarUrl: p.avatarUrl,
                                caption: p.isExternal ? 'external' : null,
                                selected: _steerers.contains(p.handle),
                                locked: p.isSelf,
                                lockHint: 'You steer this collab.',
                                onTap: () => _togglePerson(p),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Picking an agent adds their person.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: MutandeColors.stone500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _SectionLabel('Agents'),
                        const SizedBox(height: 8),
                        _ChipPane(
                          empty: _agents.isEmpty
                              ? 'Connect an AI host in Settings to add agents.'
                              : null,
                          children: [
                            for (final a in _agents)
                              _PickChip(
                                label: formatMailAddress(
                                  a.address,
                                  myHandle: widget.handle,
                                ),
                                selected: _roster.contains(a.address),
                                leading: AiHostIcon.assetFor(a.slug) == null
                                    ? null
                                    : AiHostIcon(
                                        a.slug,
                                        size: 14,
                                        showPlate: false,
                                      ),
                                trailing: TransportChip.webCaption(
                                  transport: a.transport,
                                  inverted: _roster.contains(a.address),
                                ),
                                onTap: () => _toggleAgent(a),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          collabEncryptionCopy(
                            e2e: _e2e,
                            causeAddress: _cause,
                            external: _externalCause,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: MutandeColors.stone500,
                          ),
                        ),
                        if (_showInstructions) ...[
                          const SizedBox(height: 14),
                          const _SectionLabel('Instructions'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _instructions,
                            enabled: !_busy,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Standing context for this board',
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            if (_error != null || _pickerError != null) ...[
              Text(
                _error ?? _pickerError!,
                style: const TextStyle(
                  color: MutandeColors.bronze,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    if (_pickerError != null)
                      TextButton(
                        onPressed: _busy ? null : _loadPickers,
                        child: const Text('Retry'),
                      ),
                    if (_needsSignIn)
                      TextButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('Sign in'),
                      ),
                  ],
                ),
                _CreateButton(busy: _busy, onPressed: _submit),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: MutandeColors.stone400,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _ChipPane extends StatelessWidget {
  const _ChipPane({
    required this.children,
    this.empty,
    this.maxHeight = 132,
  });

  final List<Widget> children;
  final String? empty;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Text(
        empty ?? '',
        style: const TextStyle(fontSize: 13, color: MutandeColors.stone400),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: children,
        ),
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.title,
    required this.handle,
    required this.selected,
    required this.onTap,
    this.avatarUrl,
    this.caption,
    this.locked = false,
    this.lockHint,
  });

  final String title;
  final String handle;
  final bool selected;
  final VoidCallback onTap;
  final String? avatarUrl;
  final String? caption;
  final bool locked;
  final String? lockHint;

  @override
  Widget build(BuildContext context) {
    final nameColor =
        selected ? MutandeColors.stone50 : MutandeColors.stone800;
    final handleColor = selected
        ? MutandeColors.stone50.withValues(alpha: 0.72)
        : MutandeColors.stone500;
    final initials = collabPersonInitials(title);
    final avatarBg = selected ? MutandeColors.stone50 : MutandeColors.stone100;
    final avatarFg = selected ? MutandeColors.stone800 : MutandeColors.stone600;
    final fallback = SizedBox(
      width: 28,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: avatarBg,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              color: avatarFg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
    final avatar = avatarUrl == null
        ? fallback
        : ContactAvatar(
            url: avatarUrl!,
            size: 28,
            fallback: fallback,
          );

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(maxWidth: 228, minHeight: 44),
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: selected ? MutandeColors.stone800 : MutandeColors.stone50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? MutandeColors.stone800 : MutandeColors.stone200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: handleColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(width: 6),
            Text(
              caption!,
              style: TextStyle(
                color: handleColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.1,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ],
      ),
    );

    final body = locked
        ? child
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: child,
            ),
          );

    if (locked && lockHint != null) {
      return Tooltip(message: lockHint!, child: body);
    }
    return body;
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? MutandeColors.stone50 : MutandeColors.stone800;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(maxWidth: 200, minHeight: 28),
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: selected ? MutandeColors.stone800 : MutandeColors.stone50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? MutandeColors.stone800 : MutandeColors.stone200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 5),
            trailing!,
          ],
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? () {} : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(96, 36),
        backgroundColor: MutandeColors.stone800,
        foregroundColor: MutandeColors.stone50,
        disabledBackgroundColor: MutandeColors.stone200,
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: MutandeOrb.standard(
                size: ThinkingOrbSize.inline,
                semanticLabel: 'Creating',
              ),
            )
          : const Text('Create'),
    );
  }
}
