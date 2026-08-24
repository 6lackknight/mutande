import 'dart:convert';

import '../../models/handshake_card.dart';
import '../daemon_client.dart';

/// JSON codecs for mailbox rows (round-trip view models ↔ stored blobs).
class MailboxCodec {
  static String encodeThreadDetail(ThreadDetailResult d) =>
      jsonEncode(threadDetailToJson(d));

  static ThreadDetailResult decodeThreadDetail(String raw) =>
      threadDetailFromJson(jsonDecode(raw) as Map<String, dynamic>);

  static String encodeCollabDetail(CollabDetail d) =>
      jsonEncode(collabDetailToJson(d));

  static CollabDetail decodeCollabDetail(String raw) =>
      CollabDetail.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  static String encodeCollabList({
    required List<CollabSummary> collabs,
    required CollabPortfolio portfolio,
  }) =>
      jsonEncode({
        'collabs': [for (final c in collabs) collabSummaryToJson(c)],
        'portfolio': collabPortfolioToJson(portfolio),
      });

  static ({List<CollabSummary> collabs, CollabPortfolio portfolio})
  decodeCollabList(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final collabsRaw = map['collabs'] as List<dynamic>? ?? const [];
    final collabs = [
      for (final e in collabsRaw)
        CollabSummary.fromJson(e as Map<String, dynamic>? ?? {}),
    ];
    return (
      collabs: collabs,
      portfolio: CollabPortfolio.fromJson(
        map['portfolio'] as Map<String, dynamic>?,
        collabs,
      ),
    );
  }

  static Map<String, dynamic> threadDetailToJson(ThreadDetailResult d) => {
    'id': d.id,
    'kind': d.kind,
    'status': d.status,
    'from': d.from,
    'audience': d.audience,
    if (d.yourStatus != null) 'your_status': d.yourStatus,
    if (d.awaiting.isNotEmpty)
      'awaiting': [for (final a in d.awaiting) a.toJson()],
    if (d.assignedTo != null) 'assigned_to': d.assignedTo,
    if (d.tags.isNotEmpty) 'tags': d.tags,
    if (d.dueOn != null) 'due_on': d.dueOn,
    if (d.checklist.isNotEmpty)
      'checklist': [for (final c in d.checklist) c.toJson()],
    if (d.enterpriseListingId != null)
      'enterprise_listing_id': d.enterpriseListingId,
    if (d.updatedAt != null) 'updated_at': d.updatedAt,
    if (d.pendingDowngrade != null)
      'pending_downgrade': {
        'id': d.pendingDowngrade!.id,
        'thread_id': d.pendingDowngrade!.threadId,
        'proposed_slug': d.pendingDowngrade!.proposedSlug,
        'status': d.pendingDowngrade!.status,
        if (d.pendingDowngrade!.prompt != null)
          'prompt': d.pendingDowngrade!.prompt,
      },
    if (d.pendingTaskApprovals.isNotEmpty)
      'pending_task_approvals': [
        for (final t in d.pendingTaskApprovals)
          {
            'message_id': t.messageId,
            'from_handle': t.fromHandle,
            'objective': t.objective,
            'decision': {'prompt': t.prompt},
          },
      ],
    'messages': [for (final m in d.messages) messageToJson(m)],
  };

  static ThreadDetailResult threadDetailFromJson(Map<String, dynamic> map) {
    final pendingRaw = map['pending_downgrade'] as Map<String, dynamic>?;
    final taskRaw = map['pending_task_approvals'] as List<dynamic>? ?? const [];
    return ThreadDetailResult(
      id: map['id'] as String? ?? '',
      kind: map['kind'] as String? ?? '',
      status: map['status'] as String? ?? '',
      from: map['from'] as String? ?? '',
      audience: map['audience'] as String? ?? '',
      yourStatus: map['your_status'] as String?,
      awaiting: AwaitingEntry.listFrom(map['awaiting']),
      assignedTo: map['assigned_to'] as String?,
      tags: [
        for (final t in map['tags'] as List<dynamic>? ?? const [])
          if (t is String && t.trim().isNotEmpty) t.trim().toLowerCase(),
      ],
      dueOn: map['due_on'] as String?,
      checklist: [
        for (final e in map['checklist'] as List<dynamic>? ?? const [])
          if (e is Map)
            CollabChecklistItem.fromJson(
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
            ),
      ],
      enterpriseListingId: map['enterprise_listing_id'] as String?,
      updatedAt: map['updated_at'] as String?,
      pendingDowngrade: pendingRaw == null
          ? null
          : ThreadDowngradeProposalView.fromJson(
              pendingRaw,
              prompt: pendingRaw['prompt'] as String?,
            ),
      pendingTaskApprovals: [
        for (final e in taskRaw)
          if (e is Map)
            PendingTaskApprovalView.fromJson(Map<String, dynamic>.from(e)),
      ],
      messages: [
        for (final e in map['messages'] as List<dynamic>? ?? const [])
          if (e is Map)
            messageFromJson(
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
            ),
      ],
    );
  }

  static Map<String, dynamic> messageToJson(ThreadMessageView m) => {
    'id': m.id,
    'from_handle': m.fromHandle,
    'created_at': m.createdAt,
    if (m.parentMessageId != null) 'parent_message_id': m.parentMessageId,
    if (m.inReplyTo != null) 'in_reply_to': m.inReplyTo,
    if (m.bundleSubject != null) 'bundle_subject': m.bundleSubject,
    if (m.bundleNotes != null) 'bundle_notes': m.bundleNotes,
    if (m.pingKind != null) 'ping_kind': m.pingKind,
    'has_handshake': m.hasHandshake,
    if (m.handshake != null) 'handshake': handshakeToJson(m.handshake!),
    if (m.questionPrompts.isNotEmpty) 'question_prompts': m.questionPrompts,
    if (m.resourceRequests.isNotEmpty) 'resource_requests': m.resourceRequests,
    if (m.resources.isNotEmpty)
      'resources': [for (final r in m.resources) resourceToJson(r)],
    if (m.answerTexts.isNotEmpty) 'answer_texts': m.answerTexts,
    if (m.openError != null) 'open_error': m.openError,
    if (m.upvotes != null) 'upvotes': upvotesToJson(m.upvotes!),
  };

  static ThreadMessageView messageFromJson(Map<String, dynamic> map) {
    final handshakeRaw = map['handshake'] as Map<String, dynamic>?;
    return ThreadMessageView(
      id: map['id'] as String? ?? '',
      fromHandle: map['from_handle'] as String? ?? '',
      createdAt: map['created_at'] as String? ?? '',
      parentMessageId: map['parent_message_id'] as String?,
      inReplyTo: map['in_reply_to'] as String?,
      bundleSubject: map['bundle_subject'] as String?,
      bundleNotes: map['bundle_notes'] as String?,
      pingKind: map['ping_kind'] as String?,
      hasHandshake: map['has_handshake'] == true || handshakeRaw != null,
      handshake: handshakeRaw == null
          ? null
          : HandshakeCardView.fromJson(handshakeRaw),
      questionPrompts: [
        for (final p in map['question_prompts'] as List<dynamic>? ?? const [])
          if (p is String) p,
      ],
      resourceRequests: [
        for (final p in map['resource_requests'] as List<dynamic>? ?? const [])
          if (p is String) p,
      ],
      resources: [
        for (final e in map['resources'] as List<dynamic>? ?? const [])
          if (e is Map)
            BundleResourceView.fromJson(
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
            ),
      ],
      answerTexts: [
        for (final p in map['answer_texts'] as List<dynamic>? ?? const [])
          if (p is String) p,
      ],
      openError: map['open_error'] as String?,
      upvotes: map['upvotes'] is Map
          ? MessageUpvoteSummaryView.fromJson(
              Map<String, dynamic>.from(map['upvotes'] as Map),
            )
          : null,
    );
  }

  static Map<String, dynamic> resourceToJson(BundleResourceView r) => {
    'name': r.name,
    'mime': r.mime,
    if (r.content != null) 'content': r.content,
    if (r.path != null) 'path': r.path,
    if (r.size != null) 'size': r.size,
    if (r.mediaId != null) 'media_id': r.mediaId,
  };

  static Map<String, dynamic> handshakeToJson(HandshakeCardView h) => {
    if (h.host != null) 'host': h.host,
    if (h.address != null) 'address': h.address,
    if (h.models.isNotEmpty) 'models': h.models,
    if (h.skills.isNotEmpty) 'skills': h.skills,
    if (h.askMeAbout.isNotEmpty) 'ask_me_about': h.askMeAbout,
    if (h.preferredFileFormat != null)
      'preferred_file_format': h.preferredFileFormat,
    if (h.otherTools.isNotEmpty) 'other_tools': h.otherTools,
  };

  static Map<String, dynamic> upvotesToJson(MessageUpvoteSummaryView u) => {
    'count': u.count,
    'upvotes': [
      for (final v in u.upvotes)
        {
          'agent_id': v.agentId,
          'from_handle': v.fromHandle,
          'created_at': v.createdAt,
        },
    ],
    'your_upvotes': u.yourUpvotes,
  };

  static Map<String, dynamic> collabSummaryToJson(CollabSummary c) => {
    'id': c.id,
    'name': c.name,
    'encryption_mode': c.encryptionMode,
    'status': c.status,
    'card_count': c.cardCount,
    'open': c.openCount,
    'backlog': c.backlogCount,
    'doing': c.doingCount,
    'done': c.doneCount,
    'needs_you': c.needsYouCount,
    if (c.updatedAt != null) 'updated_at': c.updatedAt,
    if (c.causeAddress != null)
      'downgrade_point': {'cause_address': c.causeAddress},
    if (c.steererHandles.isNotEmpty)
      'steerers': [
        for (final h in c.steererHandles) {'handle': h, 'user_id': ''},
      ],
    if (c.roster.isNotEmpty)
      'roster': [
        for (final r in c.roster)
          {
            'user_id': r.userId,
            'agent_id': r.agentId,
            'address': r.address,
            if (r.transport != null) 'transport': r.transport,
          },
      ],
  };

  static Map<String, dynamic> collabPortfolioToJson(CollabPortfolio p) => {
    'activity': [
      for (final a in p.activity) {'date': a.date, 'count': a.count},
    ],
    'lane_totals': {
      'backlog': p.laneTotals.backlog,
      'doing': p.laneTotals.doing,
      'done': p.laneTotals.done,
    },
    'totals': {
      'collabs': p.totals.collabs,
      'open': p.totals.open,
      'doing': p.totals.doing,
      'needs_you': p.totals.needsYou,
    },
    'recent': [
      for (final r in p.recent)
        {
          'thread_id': r.threadId,
          'collab_id': r.collabId,
          'collab_name': r.collabName,
          'from': r.from,
          'audience': r.audience,
          if (r.lastSubject != null) 'last_subject': r.lastSubject,
          if (r.updatedAt != null) 'updated_at': r.updatedAt,
          'needs_you': r.needsYou,
        },
    ],
  };

  static Map<String, dynamic> collabDetailToJson(CollabDetail d) => {
    'id': d.id,
    'name': d.name,
    'encryption_mode': d.encryptionMode,
    'status': d.status,
    'lists': [
      for (final l in d.lists)
        {'id': l.id, 'name': l.name, 'position': l.position},
    ],
    'roster': [
      for (final r in d.roster)
        {
          'user_id': r.userId,
          'agent_id': r.agentId,
          'address': r.address,
          if (r.transport != null) 'transport': r.transport,
        },
    ],
    'steerers': [
      for (final s in d.steerers) {'user_id': s.userId, 'handle': s.handle},
    ],
    'cards': [
      for (final c in d.cards) collabCardToJson(c),
    ],
    'learnings': [
      for (final l in d.learnings)
        {
          'id': l.id,
          'created_at': l.createdAt,
          'from_handle': l.fromHandle,
          if (l.notes != null) 'notes': l.notes,
          'sealed': l.sealed,
        },
    ],
    'artifacts': [
      for (final a in d.artifacts) collabArtifactToJson(a),
    ],
    if (d.instructions != null) 'instructions': d.instructions,
    if (d.memoryThreadId != null) 'memory_thread_id': d.memoryThreadId,
    if (d.createdBy != null) 'created_by': d.createdBy,
    if (d.createdAt != null) 'created_at': d.createdAt,
    if (d.updatedAt != null) 'updated_at': d.updatedAt,
    if (d.causeAddress != null)
      'downgrade_point': {'cause_address': d.causeAddress},
    if (d.pendingMembership != null)
      'pending_membership': {
        'kind': d.pendingMembership!.kind,
        'cause_address': d.pendingMembership!.causeAddress,
        'proposed_by': d.pendingMembership!.proposedBy,
        if (d.pendingMembership!.handle != null)
          'handle': d.pendingMembership!.handle,
        if (d.pendingMembership!.address != null)
          'address': d.pendingMembership!.address,
        'approved_by': d.pendingMembership!.approvedBy,
      },
  };

  static Map<String, dynamic> collabCardToJson(CollabCardView c) => {
    'id': c.id,
    if (c.laneId != null) 'lane_id': c.laneId,
    if (c.lanePosition != null) 'lane_position': c.lanePosition,
    if (c.assignedTo != null) 'assigned_to': c.assignedTo,
    'status': c.status,
    'from': c.from,
    'audience': c.audience,
    if (c.updatedAt != null) 'updated_at': c.updatedAt,
    if (c.yourStatus != null) 'your_status': c.yourStatus,
    if (c.title != null) 'title': c.title,
    if (c.tags.isNotEmpty) 'tags': c.tags,
    if (c.dueOn != null) 'due_on': c.dueOn,
    if (c.checklist.isNotEmpty)
      'checklist': [for (final i in c.checklist) i.toJson()],
  };

  static Map<String, dynamic> collabArtifactToJson(CollabArtifactView a) => {
    'kind': a.kind,
    'label': a.label,
    'url': a.url,
    'thread_id': a.threadId,
    'message_id': a.messageId,
    'card_title': a.cardTitle,
    'from_handle': a.fromHandle,
    'created_at': a.createdAt,
    ...resourceToJson(a.resource),
  };

  // —— Network (People | Agents) ——

  static String encodePeopleSnapshot({
    required List<ContactView> contacts,
    required List<ContactView> external,
    required List<PairRequestView> incoming,
    required List<PairRequestView> outgoing,
    String? selfDisplayName,
    String? selfAvatarUrl,
  }) =>
      jsonEncode({
        'contacts': [for (final c in contacts) contactToJson(c)],
        'external': [for (final c in external) contactToJson(c)],
        'incoming': [for (final p in incoming) pairRequestToJson(p)],
        'outgoing': [for (final p in outgoing) pairRequestToJson(p)],
        if (selfDisplayName != null) 'self_display_name': selfDisplayName,
        if (selfAvatarUrl != null) 'self_avatar_url': selfAvatarUrl,
      });

  static ({
    List<ContactView> contacts,
    List<ContactView> external,
    List<PairRequestView> incoming,
    List<PairRequestView> outgoing,
    String? selfDisplayName,
    String? selfAvatarUrl,
  })
  decodePeopleSnapshot(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    List<ContactView> contacts(String key) => [
      for (final e in map[key] as List<dynamic>? ?? const [])
        if (e is Map)
          ContactView.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
          ),
    ];
    List<PairRequestView> pairs(String key) => [
      for (final e in map[key] as List<dynamic>? ?? const [])
        if (e is Map)
          PairRequestView.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
          ),
    ];
    return (
      contacts: contacts('contacts'),
      external: contacts('external'),
      incoming: pairs('incoming'),
      outgoing: pairs('outgoing'),
      selfDisplayName: map['self_display_name'] as String?,
      selfAvatarUrl: map['self_avatar_url'] as String?,
    );
  }

  static String encodeAgentsSnapshot({
    required AgentListResult own,
    required List<ContactView> orgContacts,
    required List<ContactView> externalContacts,
    required Map<String, List<String>> peerAgents,
  }) =>
      jsonEncode({
        'own': agentListToJson(own),
        'org_contacts': [for (final c in orgContacts) contactToJson(c)],
        'external_contacts': [
          for (final c in externalContacts) contactToJson(c),
        ],
        'peer_agents': {
          for (final e in peerAgents.entries) e.key: e.value,
        },
      });

  static ({
    AgentListResult own,
    List<ContactView> orgContacts,
    List<ContactView> externalContacts,
    Map<String, List<String>> peerAgents,
    String? directoryError,
  })
  decodeAgentsSnapshot(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    List<ContactView> contacts(String key) => [
      for (final e in map[key] as List<dynamic>? ?? const [])
        if (e is Map)
          ContactView.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
          ),
    ];
    final peersRaw = map['peer_agents'];
    final peerAgents = <String, List<String>>{};
    if (peersRaw is Map) {
      for (final e in peersRaw.entries) {
        final slugs = e.value;
        if (slugs is! List) continue;
        peerAgents[e.key.toString()] = [
          for (final s in slugs)
            if (s is String && s.trim().isNotEmpty) s.trim().toLowerCase(),
        ];
      }
    }
    return (
      own: agentListFromJson(map['own'] as Map<String, dynamic>? ?? const {}),
      orgContacts: contacts('org_contacts'),
      externalContacts: contacts('external_contacts'),
      peerAgents: peerAgents,
      // Legacy rows may still carry this; callers should ignore for UI hydrate.
      directoryError: map['directory_error'] as String?,
    );
  }

  static Map<String, dynamic> contactToJson(ContactView c) => {
    'handle': c.handle,
    if (c.pubkey != null) 'pubkey': c.pubkey,
    if (c.devices.isNotEmpty)
      'devices': [
        for (final d in c.devices)
          {
            'pubkey': d.pubkey,
            if (d.platform != null) 'platform': d.platform,
          },
      ],
    if (c.kind != null) 'kind': c.kind,
    if (c.avatarUrl != null) 'avatar_url': c.avatarUrl,
    if (c.displayName != null) 'display_name': c.displayName,
    if (c.externalLinkId != null) 'external_link_id': c.externalLinkId,
    if (c.linkedAt != null) 'linked_at': c.linkedAt,
    if (c.threadId != null) 'thread_id': c.threadId,
  };

  static Map<String, dynamic> pairRequestToJson(PairRequestView p) => {
    'id': p.id,
    'requester_handle': p.requesterHandle,
    'target_handle': p.targetHandle,
    'status': p.status,
    'created_at': p.createdAt,
    if (p.intro != null) 'intro': p.intro,
  };

  static Map<String, dynamic> agentListToJson(AgentListResult r) => {
    if (r.defaultAgentId != null) 'default_agent_id': r.defaultAgentId,
    'agents': [for (final a in r.agents) agentToJson(a)],
  };

  static AgentListResult agentListFromJson(Map<String, dynamic> map) {
    final raw = map['agents'] as List<dynamic>? ?? const [];
    return AgentListResult(
      defaultAgentId: map['default_agent_id'] as String?,
      agents: [
        for (final e in raw)
          if (e is Map)
            AgentInfo.fromJson(
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
            ),
      ],
    );
  }

  static Map<String, dynamic> agentToJson(AgentInfo a) => {
    'id': a.id,
    'slug': a.slug,
    if (a.transport != null) 'transport': a.transport!.wireValue,
    if (a.trustTier != null) 'trust_tier': a.trustTier!.wireValue,
    if (a.lastSeen != null) 'last_seen': a.lastSeen!.toUtc().toIso8601String(),
  };
}
