import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../daemon_client.dart';
import 'mailbox_codec.dart';
import 'mailbox_crypto.dart';
import 'mailbox_database.dart';
import 'mailbox_key_store.dart';
import 'mailbox_media.dart';
import 'mailbox_paths.dart';

/// Local SQLCipher mailbox — decrypted threads/collabs/media after core open.
///
/// Hub remains source of truth. Cache after decrypt; delete on hub delete.
class MailboxStore {
  MailboxStore._({
    required this.userId,
    required this.paths,
    required this.crypto,
    required this.db,
    required this.media,
    required this.keyStore,
  });

  final String userId;
  final MailboxPaths paths;
  final MailboxCrypto crypto;
  final MailboxDatabase db;
  final MailboxMediaStore media;
  final MailboxKeyStore keyStore;

  static MailboxStore? _instance;

  /// Shared session mailbox (null until [openForUser]).
  static MailboxStore? get instance => _instance;

  /// Open or reuse the mailbox for [userId] (Auth0 sub / hub user id).
  ///
  /// Throws [MailboxKeyStoreException] / [MailboxEncryptionException] on
  /// failure — callers must fail open (leave [instance] null).
  static Future<MailboxStore> openForUser(
    String userId, {
    MailboxKeyStore? keyStore,
    String? rootOverride,
    bool encrypt = true,
    bool testMode = false,
  }) async {
    final uid = userId.trim().isEmpty ? 'anonymous' : userId.trim();
    final existing = _instance;
    if (existing != null && existing.userId == uid) return existing;
    if (existing != null) {
      await existing.close();
    }

    final keys = keyStore ?? MailboxKeyStore(testMode: testMode);
    final paths = MailboxPaths(userId: uid, rootOverride: rootOverride);
    await paths.ensureDirs();
    // Persist-or-throw — never encrypt with an ephemeral key.
    final key = await keys.getOrCreateKey(uid);
    final crypto = MailboxCrypto(key);
    final useEncrypt = encrypt && !testMode;
    final db = await MailboxDatabase.open(
      paths: paths,
      crypto: crypto,
      encrypt: useEncrypt,
    );
    final media = MailboxMediaStore(paths: paths, crypto: crypto);
    final store = MailboxStore._(
      userId: uid,
      paths: paths,
      crypto: crypto,
      db: db,
      media: media,
      keyStore: keys,
    );
    media.findMediaIdBySha = store._findMediaIdBySha;
    _instance = store;
    // Retire plaintext list cache once the encrypted mailbox is live.
    await _retireLegacyThreadListJson();
    return store;
  }

  /// In-memory mailbox for unit tests (no SQLCipher, no Keychain).
  static Future<MailboxStore> openMemory({String userId = 'test-user'}) async {
    if (_instance != null) {
      await _instance!.close();
    }
    final tmp = await Directory.systemTemp.createTemp('mutande-mailbox-mem-');
    final memPaths = MailboxPaths(userId: userId, rootOverride: tmp.path);
    await memPaths.ensureDirs();
    final keys = MailboxKeyStore(testMode: true);
    final key = await keys.getOrCreateKey(userId);
    final crypto = MailboxCrypto(key);
    final db = MailboxDatabase.memory();
    final media = MailboxMediaStore(paths: memPaths, crypto: crypto);
    final store = MailboxStore._(
      userId: userId,
      paths: memPaths,
      crypto: crypto,
      db: db,
      media: media,
      keyStore: keys,
    );
    media.findMediaIdBySha = store._findMediaIdBySha;
    _instance = store;
    return store;
  }

  Future<String?> _findMediaIdBySha(String sha) async {
    if (sha.isEmpty) return null;
    final row = await (db.select(db.mediaEntries)
          ..where((t) => t.sha256.equals(sha)))
        .getSingleOrNull();
    return row?.id;
  }

  Future<void> close() async {
    await media.clearAllPreviews();
    await db.close();
    if (_instance == this) _instance = null;
  }

  // —— Thread list ——

  Future<bool> hasRecentThreadList({
    String filter = 'all',
    Duration maxAge = const Duration(days: 7),
  }) async {
    final row = await (db.select(db.threadListSnapshots)
          ..where((t) => t.filterKey.equals(filter)))
        .getSingleOrNull();
    if (row == null) return false;
    final saved = DateTime.tryParse(row.savedAt);
    if (saved == null) return false;
    return DateTime.now().toUtc().difference(saved) <= maxAge;
  }

  Future<List<ThreadSummary>?> loadThreadList(String filter) async {
    final row = await (db.select(db.threadListSnapshots)
          ..where((t) => t.filterKey.equals(filter)))
        .getSingleOrNull();
    if (row == null) return null;
    final raw = jsonDecode(row.json);
    if (raw is! List) return null;
    return [
      for (final e in raw)
        if (e is Map)
          ThreadSummary.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
          ),
    ];
  }

  Future<void> saveThreadList(String filter, List<ThreadSummary> threads) async {
    await db
        .into(db.threadListSnapshots)
        .insertOnConflictUpdate(
          ThreadListSnapshotsCompanion.insert(
            filterKey: filter,
            savedAt: DateTime.now().toUtc().toIso8601String(),
            json: jsonEncode([for (final t in threads) t.toJson()]),
          ),
        );
  }

  // —— Thread detail ——

  Future<ThreadDetailResult?> loadThreadDetail(String threadId) async {
    final row = await (db.select(db.cachedThreadDetails)
          ..where((t) => t.id.equals(threadId)))
        .getSingleOrNull();
    if (row == null) return null;
    return MailboxCodec.decodeThreadDetail(row.json);
  }

  Future<String?> threadHubUpdatedAt(String threadId) async {
    final row = await (db.select(db.cachedThreadDetails)
          ..where((t) => t.id.equals(threadId)))
        .getSingleOrNull();
    return row?.hubUpdatedAt;
  }

  /// True when cached detail matches list fingerprint (skip get_thread).
  Future<bool> threadDetailIsFresh(
    String threadId,
    String? listUpdatedAt,
  ) async {
    final cached = await threadHubUpdatedAt(threadId);
    if (cached == null) return false;
    final list = listUpdatedAt?.trim() ?? '';
    if (list.isEmpty) return false;
    return cached == list;
  }

  Future<void> upsertThreadDetail(ThreadDetailResult detail) async {
    final previous = await loadThreadDetail(detail.id);
    final previousIds = _mediaIdsIn(previous);

    final result = await media.ingestThreadDetail(detail);
    final ingested = result.detail;
    await _writeMediaRows(detail.id, result.ingested, ingested);

    await db.into(db.cachedThreadDetails).insertOnConflictUpdate(
          CachedThreadDetailsCompanion.insert(
            id: ingested.id,
            hubUpdatedAt: Value(ingested.updatedAt),
            json: MailboxCodec.encodeThreadDetail(ingested),
            cachedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

    final nextIds = _mediaIdsIn(ingested);
    await _purgeOrphanMedia(previousIds.difference(nextIds));
  }

  Future<void> deleteThread(String threadId) async {
    final detail = await loadThreadDetail(threadId);
    final ids = _mediaIdsIn(detail);
    await (db.delete(db.cachedThreadDetails)..where((t) => t.id.equals(threadId)))
        .go();
    await _purgeOrphanMedia(ids);
    final snaps = await db.select(db.threadListSnapshots).get();
    for (final snap in snaps) {
      final raw = jsonDecode(snap.json);
      if (raw is! List) continue;
      final next = [
        for (final e in raw)
          if (e is Map && (e['id'] as String?) != threadId) e,
      ];
      if (next.length == raw.length) continue;
      await db
          .into(db.threadListSnapshots)
          .insertOnConflictUpdate(
            ThreadListSnapshotsCompanion.insert(
              filterKey: snap.filterKey,
              savedAt: snap.savedAt,
              json: jsonEncode(next),
            ),
          );
    }
  }

  Set<String> _mediaIdsIn(ThreadDetailResult? detail) {
    if (detail == null) return {};
    return {
      for (final msg in detail.messages)
        for (final r in msg.resources)
          if (r.mediaId != null && r.mediaId!.trim().isNotEmpty) r.mediaId!.trim(),
    };
  }

  /// Drop media files no longer referenced by any cached thread/collab.
  Future<void> _purgeOrphanMedia(Set<String> candidates) async {
    for (final mid in candidates) {
      final stillUsed = await _mediaIdStillReferenced(mid);
      if (stillUsed) continue;
      await media.deleteEncrypted(mid);
      await (db.delete(db.mediaEntries)..where((t) => t.id.equals(mid))).go();
    }
  }

  Future<bool> _mediaIdStillReferenced(String mediaId) async {
    final threads = await db.select(db.cachedThreadDetails).get();
    for (final row in threads) {
      if (row.json.contains(mediaId)) return true;
    }
    final collabs = await db.select(db.cachedCollabDetails).get();
    for (final row in collabs) {
      if (row.json.contains(mediaId)) return true;
    }
    return false;
  }

  Future<void> _writeMediaRows(
    String threadId,
    List<IngestedResource> ingested,
    ThreadDetailResult detail,
  ) async {
    // Index by mediaId → sha from ingest metadata.
    final shaById = <String, String>{
      for (final i in ingested)
        if (i.resource.mediaId != null && i.sha256.isNotEmpty)
          i.resource.mediaId!: i.sha256,
    };
    final pathById = <String, String>{
      for (final i in ingested)
        if (i.resource.mediaId != null && i.encryptedPath.isNotEmpty)
          i.resource.mediaId!: i.encryptedPath,
    };

    for (final msg in detail.messages) {
      for (final r in msg.resources) {
        final mid = r.mediaId;
        if (mid == null || mid.isEmpty) continue;
        final encPath =
            pathById[mid] ?? p.join(paths.mediaDir, '$mid.enc');
        await db.into(db.mediaEntries).insertOnConflictUpdate(
              MediaEntriesCompanion.insert(
                id: mid,
                sha256: shaById[mid] ?? '',
                threadId: Value(threadId),
                messageId: Value(msg.id),
                name: r.name,
                mime: r.mime,
                size: Value(r.size),
                encryptedPath: encPath,
                cachedAt: DateTime.now().toUtc().toIso8601String(),
              ),
            );
      }
    }
  }

  /// Resolve media for UI open/preview — decrypts to preview cache.
  /// Prefers an existing on-disk path; otherwise mailbox mediaId.
  Future<String?> resolveMediaPath(BundleResourceView resource) async {
    if (resource.hasPath) {
      final path = resource.path!.trim();
      if (path.isNotEmpty && await File(path).exists()) return path;
    }
    final mid = resource.mediaId;
    if (mid == null || mid.isEmpty) return null;
    final row = await (db.select(db.mediaEntries)
          ..where((t) => t.id.equals(mid)))
        .getSingleOrNull();
    return media.materializePreview(
      mediaId: mid,
      name: resource.name,
      encryptedPath: row?.encryptedPath,
    );
  }

  Future<void> clearPreviewsForDetail(ThreadDetailResult? detail) async {
    if (detail == null) return;
    await media.clearPreviewsForMediaIds(_mediaIdsIn(detail));
  }

  // —— Collabs ——

  Future<({List<CollabSummary> collabs, CollabPortfolio portfolio})?>
  loadCollabList({bool archived = false}) async {
    final key = archived ? 'archived' : 'active';
    final row = await (db.select(db.collabListSnapshots)
          ..where((t) => t.archiveKey.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return MailboxCodec.decodeCollabList(row.json);
  }

  Future<void> saveCollabList({
    required List<CollabSummary> collabs,
    required CollabPortfolio portfolio,
    bool archived = false,
  }) async {
    final key = archived ? 'archived' : 'active';
    await db.into(db.collabListSnapshots).insertOnConflictUpdate(
          CollabListSnapshotsCompanion.insert(
            archiveKey: key,
            savedAt: DateTime.now().toUtc().toIso8601String(),
            json: MailboxCodec.encodeCollabList(
              collabs: collabs,
              portfolio: portfolio,
            ),
          ),
        );
  }

  Future<CollabDetail?> loadCollabDetail(String collabId) async {
    final row = await (db.select(db.cachedCollabDetails)
          ..where((t) => t.id.equals(collabId)))
        .getSingleOrNull();
    if (row == null) return null;
    return MailboxCodec.decodeCollabDetail(row.json);
  }

  Future<bool> collabDetailIsFresh(
    String collabId,
    String? listUpdatedAt,
  ) async {
    final row = await (db.select(db.cachedCollabDetails)
          ..where((t) => t.id.equals(collabId)))
        .getSingleOrNull();
    if (row == null) return false;
    final list = listUpdatedAt?.trim() ?? '';
    if (list.isEmpty || row.hubUpdatedAt == null) return false;
    return row.hubUpdatedAt == list;
  }

  Future<void> upsertCollabDetail(
    CollabDetail detail, {
    /// List-row stamp (`last_card_updated_at` / `updated_at`) so reopen can
    /// skip `get_collab` when the home list fingerprint is unchanged.
    String? listFingerprint,
  }) async {
    final previous = await loadCollabDetail(detail.id);
    final previousIds = _collabMediaIds(previous);

    final artifacts = <CollabArtifactView>[];
    for (final a in detail.artifacts) {
      if (a.isLink) {
        artifacts.add(a);
        continue;
      }
      final result = await media.ingestThreadDetail(
        ThreadDetailResult(
          id: a.threadId,
          kind: 'collab',
          status: 'open',
          from: a.fromHandle,
          updatedAt: a.createdAt,
          messages: [
            ThreadMessageView(
              id: a.messageId,
              fromHandle: a.fromHandle,
              createdAt: a.createdAt,
              resources: [a.resource],
            ),
          ],
        ),
      );
      final ingested = result.detail;
      final r = ingested.messages.isNotEmpty &&
              ingested.messages.first.resources.isNotEmpty
          ? ingested.messages.first.resources.first
          : a.resource;
      artifacts.add(
        CollabArtifactView(
          kind: a.kind,
          label: a.label,
          url: a.url,
          threadId: a.threadId,
          messageId: a.messageId,
          cardTitle: a.cardTitle,
          fromHandle: a.fromHandle,
          createdAt: a.createdAt,
          resource: r,
        ),
      );
      await _writeMediaRows(a.threadId, result.ingested, ingested);
    }

    final stored = CollabDetail(
      id: detail.id,
      name: detail.name,
      encryptionMode: detail.encryptionMode,
      lists: detail.lists,
      status: detail.status,
      roster: detail.roster,
      steerers: detail.steerers,
      steererHandles: detail.steererHandles,
      cards: detail.cards,
      learnings: detail.learnings,
      artifacts: artifacts,
      instructions: detail.instructions,
      memoryThreadId: detail.memoryThreadId,
      createdBy: detail.createdBy,
      createdAt: detail.createdAt,
      updatedAt: detail.updatedAt,
      causeAddress: detail.causeAddress,
      pendingMembership: detail.pendingMembership,
    );

    final fp = listFingerprint?.trim();
    final hubStamp =
        (fp != null && fp.isNotEmpty) ? fp : stored.updatedAt;

    await db.into(db.cachedCollabDetails).insertOnConflictUpdate(
          CachedCollabDetailsCompanion.insert(
            id: stored.id,
            hubUpdatedAt: Value(hubStamp),
            json: MailboxCodec.encodeCollabDetail(stored),
            cachedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

    final nextIds = _collabMediaIds(stored);
    await _purgeOrphanMedia(previousIds.difference(nextIds));
  }

  Set<String> _collabMediaIds(CollabDetail? detail) {
    if (detail == null) return {};
    return {
      for (final a in detail.artifacts)
        if (a.resource.mediaId != null && a.resource.mediaId!.trim().isNotEmpty)
          a.resource.mediaId!.trim(),
    };
  }

  Future<void> deleteCollab(String collabId) async {
    final detail = await loadCollabDetail(collabId);
    final ids = _collabMediaIds(detail);
    await (db.delete(db.cachedCollabDetails)..where((t) => t.id.equals(collabId)))
        .go();
    // Scrub from list snapshots.
    for (final key in ['active', 'archived']) {
      final row = await (db.select(db.collabListSnapshots)
            ..where((t) => t.archiveKey.equals(key)))
          .getSingleOrNull();
      if (row == null) continue;
      final decoded = MailboxCodec.decodeCollabList(row.json);
      final next = [
        for (final c in decoded.collabs)
          if (c.id != collabId) c,
      ];
      if (next.length == decoded.collabs.length) continue;
      await saveCollabList(
        collabs: next,
        portfolio: decoded.portfolio,
        archived: key == 'archived',
      );
    }
    await _purgeOrphanMedia(ids);
  }

  // —— Network (People | Agents) ——

  Future<({
    List<ContactView> contacts,
    List<ContactView> external,
    List<PairRequestView> incoming,
    List<PairRequestView> outgoing,
    String? selfDisplayName,
    String? selfAvatarUrl,
  })?>
  loadPeopleSnapshot() async {
    final row = await (db.select(db.networkSnapshots)
          ..where((t) => t.kind.equals('people')))
        .getSingleOrNull();
    if (row == null) return null;
    return MailboxCodec.decodePeopleSnapshot(row.json);
  }

  /// Persist people directory. Null fields keep the previous snapshot value
  /// so a partial hub failure cannot wipe pairing / external rows.
  Future<void> savePeopleSnapshot({
    List<ContactView>? contacts,
    List<ContactView>? external,
    List<PairRequestView>? incoming,
    List<PairRequestView>? outgoing,
    String? selfDisplayName,
    String? selfAvatarUrl,
    bool updateSelfProfile = false,
  }) async {
    final prev = await loadPeopleSnapshot();
    await db.into(db.networkSnapshots).insertOnConflictUpdate(
          NetworkSnapshotsCompanion.insert(
            kind: 'people',
            savedAt: DateTime.now().toUtc().toIso8601String(),
            json: MailboxCodec.encodePeopleSnapshot(
              contacts: contacts ?? prev?.contacts ?? const [],
              external: external ?? prev?.external ?? const [],
              incoming: incoming ?? prev?.incoming ?? const [],
              outgoing: outgoing ?? prev?.outgoing ?? const [],
              selfDisplayName: updateSelfProfile
                  ? selfDisplayName
                  : prev?.selfDisplayName,
              selfAvatarUrl: updateSelfProfile
                  ? selfAvatarUrl
                  : prev?.selfAvatarUrl,
            ),
          ),
        );
  }

  Future<({
    AgentListResult own,
    List<ContactView> orgContacts,
    List<ContactView> externalContacts,
    Map<String, List<String>> peerAgents,
    String? directoryError,
  })?>
  loadAgentsSnapshot() async {
    final row = await (db.select(db.networkSnapshots)
          ..where((t) => t.kind.equals('agents')))
        .getSingleOrNull();
    if (row == null) return null;
    return MailboxCodec.decodeAgentsSnapshot(row.json);
  }

  /// Persist agents graph. Null fields keep the previous snapshot value.
  /// Does not persist [directoryError] (transient UI only).
  Future<void> saveAgentsSnapshot({
    AgentListResult? own,
    List<ContactView>? orgContacts,
    List<ContactView>? externalContacts,
    Map<String, List<String>>? peerAgents,
  }) async {
    final prev = await loadAgentsSnapshot();
    final nextOwn = own ??
        prev?.own ??
        const AgentListResult(agents: []);
    await db.into(db.networkSnapshots).insertOnConflictUpdate(
          NetworkSnapshotsCompanion.insert(
            kind: 'agents',
            savedAt: DateTime.now().toUtc().toIso8601String(),
            json: MailboxCodec.encodeAgentsSnapshot(
              own: nextOwn,
              orgContacts: orgContacts ?? prev?.orgContacts ?? const [],
              externalContacts:
                  externalContacts ?? prev?.externalContacts ?? const [],
              peerAgents: peerAgents ?? prev?.peerAgents ?? const {},
            ),
          ),
        );
  }
}

/// Delete pre-mailbox plaintext list cache under `~/.mutande/`.
Future<void> _retireLegacyThreadListJson() async {
  try {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return;
    final file = File('$home/.mutande/thread_list_cache.json');
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}
