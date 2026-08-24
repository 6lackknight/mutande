import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/daemon_client.dart';
import 'package:app/services/mailbox/mailbox_crypto.dart';
import 'package:app/services/mailbox/mailbox_database.dart';
import 'package:app/services/mailbox/mailbox_key_store.dart';
import 'package:app/services/mailbox/mailbox_paths.dart';
import 'package:app/services/mailbox/mailbox_store.dart';
import 'package:app/widgets/message_attachments.dart';

void main() {
  late MailboxStore store;

  setUp(() async {
    store = await MailboxStore.openMemory(userId: 'test-user');
  });

  tearDown(() async {
    await store.close();
  });

  test('thread list round-trips', () async {
    const threads = [
      ThreadSummary(
        id: 't1',
        kind: 'direct',
        status: 'open',
        from: 'alice@acme',
        audience: 'bob@acme',
        updatedAt: '2026-08-21T12:00:00Z',
        lastPreview: 'hello',
      ),
    ];
    await store.saveThreadList('all', threads);
    expect(await store.hasRecentThreadList(), isTrue);
    final loaded = await store.loadThreadList('all');
    expect(loaded, isNotNull);
    expect(loaded!.single.sameListRow(threads.single), isTrue);
  });

  test('thread detail round-trip + freshness fingerprint', () async {
    final detail = ThreadDetailResult(
      id: 't1',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme',
      updatedAt: '2026-08-21T12:00:00Z',
      messages: [
        ThreadMessageView(
          id: 'm1',
          fromHandle: 'alice@acme/cursor',
          createdAt: '2026-08-21T12:00:00Z',
          bundleSubject: 'Hi',
          bundleNotes: 'Body',
        ),
      ],
    );
    await store.upsertThreadDetail(detail);

    final loaded = await store.loadThreadDetail('t1');
    expect(loaded, isNotNull);
    expect(loaded!.id, 't1');
    expect(loaded.messages.single.bundleSubject, 'Hi');

    expect(
      await store.threadDetailIsFresh('t1', '2026-08-21T12:00:00Z'),
      isTrue,
    );
    expect(
      await store.threadDetailIsFresh('t1', '2026-08-21T13:00:00Z'),
      isFalse,
    );
    expect(await store.threadDetailIsFresh('missing', 'x'), isFalse);
  });

  test('open recreates mailbox when existing file is not a database', () async {
    final tmp = await Directory.systemTemp.createTemp('mutande-mailbox-bad-');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
    final paths = MailboxPaths(userId: 'bad-db-user', rootOverride: tmp.path);
    await paths.ensureDirs();
    await File(paths.dbPath).writeAsBytes([0x00, 0x01, 0x02, 0x03, 0xff]);

    final key = List<int>.generate(32, (i) => i + 1);
    final crypto = MailboxCrypto(Uint8List.fromList(key));
    final db = await MailboxDatabase.open(
      paths: paths,
      crypto: crypto,
      encrypt: false,
    );
    addTearDown(() async {
      await db.close();
    });
    await db.customSelect('SELECT 1').get();
    expect(await File(paths.dbPath).exists(), isTrue);
  });

  test('delete_thread purges local rows and .enc files', () async {
    final dir = await Directory.systemTemp.createTemp('mutande-del-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plain = File('${dir.path}/note.txt');
    await plain.writeAsString('bye');

    final detail = ThreadDetailResult(
      id: 't-del',
      kind: 'direct',
      status: 'open',
      from: 'alice@acme',
      updatedAt: '2026-08-21T12:00:00Z',
      messages: [
        ThreadMessageView(
          id: 'm1',
          fromHandle: 'alice@acme',
          createdAt: '2026-08-21T12:00:00Z',
          resources: [
            BundleResourceView(
              name: 'note.txt',
              mime: 'text/plain',
              path: plain.path,
            ),
          ],
        ),
      ],
    );
    await store.upsertThreadDetail(detail);
    final cached = await store.loadThreadDetail('t-del');
    final mid = cached!.messages.single.resources.single.mediaId!;
    final enc = File('${store.paths.mediaDir}/$mid.enc');
    expect(await enc.exists(), isTrue);

    await store.saveThreadList('all', [
      ThreadSummary(
        id: 't-del',
        kind: 'direct',
        status: 'open',
        from: 'alice@acme',
        audience: 'bob@acme',
        updatedAt: '2026-08-21T12:00:00Z',
      ),
    ]);

    await store.deleteThread('t-del');
    expect(await store.loadThreadDetail('t-del'), isNull);
    expect(await enc.exists(), isFalse);
    final list = await store.loadThreadList('all');
    expect(list!.where((t) => t.id == 't-del'), isEmpty);
  });

  test('media dedupe by sha256 — re-upsert does not orphan .enc', () async {
    final dir = await Directory.systemTemp.createTemp('mutande-dedupe-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plain = File('${dir.path}/note.txt');
    await plain.writeAsString('same bytes');

    BundleResourceView res(String path) => BundleResourceView(
      name: 'note.txt',
      mime: 'text/plain',
      path: path,
    );

    Future<ThreadDetailResult> detail(String updatedAt) async =>
        ThreadDetailResult(
          id: 't-media',
          kind: 'direct',
          status: 'open',
          from: 'alice@acme',
          updatedAt: updatedAt,
          messages: [
            ThreadMessageView(
              id: 'm1',
              fromHandle: 'alice@acme',
              createdAt: updatedAt,
              resources: [res(plain.path)],
            ),
          ],
        );

    await store.upsertThreadDetail(await detail('2026-08-21T12:00:00Z'));
    final first = await store.loadThreadDetail('t-media');
    final mid1 = first!.messages.single.resources.single.mediaId!;

    await store.upsertThreadDetail(await detail('2026-08-21T13:00:00Z'));
    final second = await store.loadThreadDetail('t-media');
    final mid2 = second!.messages.single.resources.single.mediaId!;
    expect(mid2, mid1);

    final encFiles = Directory(store.paths.mediaDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.enc'));
    expect(encFiles.length, 1);

    final preview = await store.resolveMediaPath(
      second.messages.single.resources.single,
    );
    expect(preview, isNotNull);
    expect(await File(preview!).readAsString(), 'same bytes');

    final wrong = MailboxCrypto(Uint8List.fromList(List.filled(32, 7)));
    final sealed = await File('${store.paths.mediaDir}/$mid1.enc').readAsBytes();
    expect(() => wrong.decrypt(sealed), throwsA(isA<Object>()));
  });

  test('resolveAttachmentPath falls through when path is missing', () async {
    final dir = await Directory.systemTemp.createTemp('mutande-resolve-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plain = File('${dir.path}/note.txt');
    await plain.writeAsString('via media');

    await store.upsertThreadDetail(
      ThreadDetailResult(
        id: 't-r',
        kind: 'direct',
        status: 'open',
        from: 'a@acme',
        updatedAt: '2026-08-21T12:00:00Z',
        messages: [
          ThreadMessageView(
            id: 'm1',
            fromHandle: 'a@acme',
            createdAt: '2026-08-21T12:00:00Z',
            resources: [
              BundleResourceView(
                name: 'note.txt',
                mime: 'text/plain',
                path: plain.path,
              ),
            ],
          ),
        ],
      ),
    );
    final cached = await store.loadThreadDetail('t-r');
    final mid = cached!.messages.single.resources.single.mediaId!;

    // Stale core path + mediaId — must use mailbox.
    final stale = BundleResourceView(
      name: 'note.txt',
      mime: 'text/plain',
      path: '${dir.path}/gone.txt',
      mediaId: mid,
    );
    final path = await resolveAttachmentPath(stale);
    expect(path, isNotNull);
    expect(await File(path!).readAsString(), 'via media');
  });

  test('collab detail round-trip + freshness', () async {
    const detail = CollabDetail(
      id: 'c1',
      name: 'Pilot',
      encryptionMode: 'e2e',
      lists: [],
      updatedAt: '2026-08-21T12:00:00Z',
    );
    await store.upsertCollabDetail(detail);
    final loaded = await store.loadCollabDetail('c1');
    expect(loaded?.name, 'Pilot');
    expect(await store.collabDetailIsFresh('c1', '2026-08-21T12:00:00Z'), isTrue);
    expect(await store.collabDetailIsFresh('c1', 'stale'), isFalse);
  });

  test('collab freshness uses list fingerprint when provided', () async {
    const detail = CollabDetail(
      id: 'c2',
      name: 'Pilot',
      encryptionMode: 'e2e',
      lists: [],
      updatedAt: '2026-08-21T12:00:00Z',
    );
    // Home list uses last_card_updated_at — often ≠ detail.updated_at.
    await store.upsertCollabDetail(
      detail,
      listFingerprint: '2026-08-21T14:00:00Z',
    );
    expect(
      await store.collabDetailIsFresh('c2', '2026-08-21T14:00:00Z'),
      isTrue,
    );
    expect(
      await store.collabDetailIsFresh('c2', '2026-08-21T12:00:00Z'),
      isFalse,
    );
  });

  test('Keychain write failure throws (no ephemeral key)', () async {
    final failing = _FailingWriteKeyStore();
    expect(
      () => failing.getOrCreateKey('user-x'),
      throwsA(isA<MailboxKeyStoreException>()),
    );
  });

  test('SQLCipher wrong key cannot read encrypted mailbox file', () async {
    final dir = await Directory.systemTemp.createTemp('mutande-cipher-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = MailboxPaths(userId: 'cipher', rootOverride: dir.path);
    await paths.ensureDirs();

    final keyA = await MailboxKeyStore(testMode: true).getOrCreateKey('cipher-a');
    final keyB = Uint8List.fromList(List.filled(32, 9));
    final cryptoA = MailboxCrypto(keyA);
    final cryptoB = MailboxCrypto(keyB);

    // Prefer real SQLCipher when hooks linked it; otherwise skip.
    try {
      await MailboxDatabase.open(
        paths: paths,
        crypto: cryptoA,
        encrypt: true,
        requireSqlCipher: true,
      ).then((db) async {
        await db
            .into(db.threadListSnapshots)
            .insert(
              ThreadListSnapshotsCompanion.insert(
                filterKey: 'all',
                savedAt: DateTime.now().toUtc().toIso8601String(),
                json: '[]',
              ),
            );
        await db.close();
      });
    } on MailboxEncryptionException {
      // Stock SQLite in this environment — probe correctly refused.
      return;
    }

    // Re-open same file with a different key — must fail under SQLCipher.
    expect(
      () async {
        final db = await MailboxDatabase.open(
          paths: paths,
          crypto: cryptoB,
          encrypt: true,
          requireSqlCipher: true,
        );
        try {
          await db.select(db.threadListSnapshots).get();
        } finally {
          await db.close();
        }
      }(),
      throwsA(anything),
    );
  });

  test('people snapshot round-trips', () async {
    await store.savePeopleSnapshot(
      contacts: const [
        ContactView(handle: 'alice@acme', displayName: 'Alice'),
        ContactView(handle: '@all@acme', kind: 'broadcast'),
      ],
      external: const [
        ContactView(handle: 'bob@other', kind: 'external'),
      ],
      incoming: const [
        PairRequestView(
          id: 'p1',
          requesterHandle: 'carol@x',
          targetHandle: 'alice@acme',
          status: 'pending',
          createdAt: '2026-08-21T12:00:00Z',
        ),
      ],
      outgoing: const [],
      selfDisplayName: 'Alice',
      selfAvatarUrl: 'https://example.com/a.png',
      updateSelfProfile: true,
    );
    final loaded = await store.loadPeopleSnapshot();
    expect(loaded, isNotNull);
    expect(loaded!.contacts.map((c) => c.handle).toList(), [
      'alice@acme',
      '@all@acme',
    ]);
    expect(loaded.external.single.handle, 'bob@other');
    expect(loaded.incoming.single.id, 'p1');
    expect(loaded.selfDisplayName, 'Alice');
    expect(loaded.selfAvatarUrl, 'https://example.com/a.png');
  });

  test('people merge keeps pairing when only contacts update', () async {
    await store.savePeopleSnapshot(
      contacts: const [ContactView(handle: 'alice@acme')],
      external: const [ContactView(handle: 'bob@other', kind: 'external')],
      incoming: const [
        PairRequestView(
          id: 'p1',
          requesterHandle: 'carol@x',
          targetHandle: 'alice@acme',
          status: 'pending',
          createdAt: '2026-08-21T12:00:00Z',
        ),
      ],
      outgoing: const [],
    );
    await store.savePeopleSnapshot(
      contacts: const [
        ContactView(handle: 'alice@acme'),
        ContactView(handle: 'dave@acme'),
      ],
      // pairing fields omitted → keep previous
    );
    final loaded = await store.loadPeopleSnapshot();
    expect(loaded!.contacts.map((c) => c.handle).toList(), [
      'alice@acme',
      'dave@acme',
    ]);
    expect(loaded.external.single.handle, 'bob@other');
    expect(loaded.incoming.single.id, 'p1');
  });

  test('people merge persists empty external list', () async {
    await store.savePeopleSnapshot(
      contacts: const [ContactView(handle: 'alice@acme')],
      external: const [ContactView(handle: 'bob@other', kind: 'external')],
      incoming: const [],
      outgoing: const [],
    );
    await store.savePeopleSnapshot(
      contacts: const [ContactView(handle: 'alice@acme')],
      external: const [],
      incoming: const [],
      outgoing: const [],
    );
    final loaded = await store.loadPeopleSnapshot();
    expect(loaded!.external, isEmpty);
  });

  test('agents snapshot round-trips peer graph', () async {
    await store.saveAgentsSnapshot(
      own: const AgentListResult(
        defaultAgentId: 'a1',
        agents: [
          AgentInfo(id: 'a1', slug: 'cursor'),
          AgentInfo(id: 'a2', slug: 'claude'),
        ],
      ),
      orgContacts: const [
        ContactView(handle: 'alice@acme'),
        ContactView(handle: 'bob@acme'),
      ],
      externalContacts: const [],
      peerAgents: {
        'alice@acme': ['cursor', 'claude'],
        'bob@acme': ['chatgpt'],
      },
    );
    final loaded = await store.loadAgentsSnapshot();
    expect(loaded, isNotNull);
    expect(loaded!.own.defaultAgentId, 'a1');
    expect(loaded.own.agents.map((a) => a.slug).toList(), [
      'cursor',
      'claude',
    ]);
    expect(loaded.orgContacts.map((c) => c.handle).toList(), [
      'alice@acme',
      'bob@acme',
    ]);
    expect(loaded.peerAgents['bob@acme'], ['chatgpt']);
  });

  test('agents merge keeps org when only own agents update', () async {
    await store.saveAgentsSnapshot(
      own: const AgentListResult(
        agents: [AgentInfo(id: 'a1', slug: 'cursor')],
      ),
      orgContacts: const [ContactView(handle: 'bob@acme')],
      externalContacts: const [
        ContactView(handle: 'eve@x', kind: 'external'),
      ],
      peerAgents: {
        'bob@acme': ['claude'],
      },
    );
    await store.saveAgentsSnapshot(
      own: const AgentListResult(
        agents: [
          AgentInfo(id: 'a1', slug: 'cursor'),
          AgentInfo(id: 'a2', slug: 'chatgpt'),
        ],
      ),
    );
    final loaded = await store.loadAgentsSnapshot();
    expect(loaded!.own.agents.map((a) => a.slug).toList(), [
      'cursor',
      'chatgpt',
    ]);
    expect(loaded.orgContacts.single.handle, 'bob@acme');
    expect(loaded.externalContacts.single.handle, 'eve@x');
    expect(loaded.peerAgents['bob@acme'], ['claude']);
  });

  test('agents merge persists empty external contacts', () async {
    await store.saveAgentsSnapshot(
      own: const AgentListResult(agents: []),
      orgContacts: const [],
      externalContacts: const [
        ContactView(handle: 'eve@x', kind: 'external'),
      ],
      peerAgents: const {},
    );
    await store.saveAgentsSnapshot(externalContacts: const []);
    final loaded = await store.loadAgentsSnapshot();
    expect(loaded!.externalContacts, isEmpty);
  });
}

class _FailingWriteKeyStore extends MailboxKeyStore {
  _FailingWriteKeyStore()
    : super(
        storage: _ThrowOnWriteStorage(),
        testMode: false,
        allowTestEnvBypass: false,
      );
}

class _ThrowOnWriteStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    throw StateError('keychain denied');
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async => null;
}
