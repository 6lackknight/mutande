import '../services/daemon_client.dart';
import '../util/thread_peer.dart';
import 'thread_repository.dart';

/// People + Agents directory — snapshot merge, soft revalidate.
class NetworkRepository {
  NetworkRepository({
    required this.daemon,
    required this.mailbox,
    this.onMailboxChanged,
  });

  final DaemonClient daemon;
  final MailboxGetter mailbox;
  final void Function()? onMailboxChanged;

  void _tick() => onMailboxChanged?.call();

  Future<void> refreshPeople() async {
    final contacts = await daemon.listContacts();
    List<ContactView>? external;
    List<PairRequestView>? incoming;
    List<PairRequestView>? outgoing;
    var pairingOk = false;
    String? selfDisplayName;
    String? selfAvatarUrl;
    var selfOk = false;
    try {
      final status = await daemon.getStatus();
      selfDisplayName = status.displayName;
      selfAvatarUrl = status.avatarUrl;
      selfOk = true;
    } catch (_) {}
    try {
      external = await daemon.listExternalContacts();
      final pending = await daemon.listPendingPairRequests();
      incoming = pending.incoming;
      outgoing = pending.outgoing;
      pairingOk = true;
    } catch (_) {}
    final box = mailbox();
    if (box != null) {
      try {
        await box.savePeopleSnapshot(
          contacts: contacts,
          external: pairingOk ? external : null,
          incoming: pairingOk ? incoming : null,
          outgoing: pairingOk ? outgoing : null,
          selfDisplayName: selfDisplayName,
          selfAvatarUrl: selfAvatarUrl,
          updateSelfProfile: selfOk,
        );
        _tick();
      } catch (_) {}
    }
  }

  Future<void> refreshAgents({String? handle}) async {
    final list = await daemon.listAgents();
    var org = const <ContactView>[];
    var external = const <ContactView>[];
    var orgOk = false;
    var externalOk = false;
    try {
      org = await daemon.listContacts();
      orgOk = true;
    } catch (_) {}
    try {
      external = await daemon.listExternalContacts();
      externalOk = true;
    } catch (_) {}

    final mine = handle?.trim();
    final peerAgents = <String, List<String>>{
      if (mine != null && mine.isNotEmpty)
        bareMailHandle(mine): _uniqueSlugs(list.agents),
    };
    if (orgOk) {
      final room = (mine != null && mine.isNotEmpty) ? 11 : 12;
      final peers = org
          .where((c) => !c.isBroadcast && c.handle.trim().isNotEmpty)
          .take(room)
          .toList();
      await Future.wait([
        for (final c in peers)
          () async {
            try {
              final peer = await daemon.listAgents(handle: c.handle);
              peerAgents[bareMailHandle(c.handle)] = _uniqueSlugs(peer.agents);
            } catch (_) {}
          }(),
      ]);
    }

    final box = mailbox();
    if (box != null) {
      try {
        await box.saveAgentsSnapshot(
          own: list,
          orgContacts: orgOk ? org : null,
          externalContacts: externalOk ? external : null,
          peerAgents: peerAgents,
        );
        _tick();
      } catch (_) {}
    }
  }

  static List<String> _uniqueSlugs(Iterable<AgentInfo> agents) {
    final seen = <String>{};
    final out = <String>[];
    for (final a in agents) {
      final s = a.slug.trim().toLowerCase();
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
    }
    return out;
  }
}
