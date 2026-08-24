import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'mailbox_crypto.dart';
import 'mailbox_paths.dart';

part 'mailbox_database.g.dart';

class ThreadListSnapshots extends Table {
  TextColumn get filterKey => text()();
  TextColumn get savedAt => text()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {filterKey};
}

class CachedThreadDetails extends Table {
  TextColumn get id => text()();
  TextColumn get hubUpdatedAt => text().nullable()();
  TextColumn get json => text()();
  TextColumn get cachedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class CollabListSnapshots extends Table {
  TextColumn get archiveKey => text()();
  TextColumn get savedAt => text()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {archiveKey};
}

class CachedCollabDetails extends Table {
  TextColumn get id => text()();
  TextColumn get hubUpdatedAt => text().nullable()();
  TextColumn get json => text()();
  TextColumn get cachedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class MediaEntries extends Table {
  TextColumn get id => text()();
  TextColumn get sha256 => text()();
  TextColumn get threadId => text().nullable()();
  TextColumn get messageId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get mime => text()();
  IntColumn get size => integer().nullable()();
  TextColumn get encryptedPath => text()();
  TextColumn get cachedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// People / Agents directory snapshots (`people` | `agents`).
class NetworkSnapshots extends Table {
  TextColumn get kind => text()();
  TextColumn get savedAt => text()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {kind};
}

/// Thrown when encryption was requested but the linked SQLite is not SQLCipher.
class MailboxEncryptionException implements Exception {
  MailboxEncryptionException(this.message);
  final String message;
  @override
  String toString() => 'MailboxEncryptionException: $message';
}

@DriftDatabase(
  tables: [
    ThreadListSnapshots,
    CachedThreadDetails,
    CollabListSnapshots,
    CachedCollabDetails,
    MediaEntries,
    NetworkSnapshots,
  ],
)
class MailboxDatabase extends _$MailboxDatabase {
  MailboxDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(networkSnapshots);
      }
    },
  );

  /// Open SQLCipher (prod) or plain SQLite (tests / encrypt=false).
  ///
  /// SQLCipher is enabled via pubspec `hooks.user_defines.sqlite3.source: sqlcipher`.
  /// Set [requireSqlCipher] to force the probe even under `FLUTTER_TEST`
  /// (expects failure on stock SQLite).
  ///
  /// If an existing file cannot be opened with [crypto]'s key (Keychain rotated,
  /// corrupt file), the DB files are deleted and a fresh mailbox is created.
  static Future<MailboxDatabase> open({
    required MailboxPaths paths,
    required MailboxCrypto crypto,
    bool encrypt = true,
    bool requireSqlCipher = false,
    bool alreadyRecreated = false,
  }) async {
    await paths.ensureDirs();
    final file = File(paths.dbPath);
    final wantEncrypt =
        (encrypt && !_usePlainSqlite) || requireSqlCipher;

    if (wantEncrypt) {
      await _assertSqlCipherLinked(crypto);
    }

    if (await file.exists()) {
      final readable = await _dbReadableWithKey(
        paths.dbPath,
        wantEncrypt ? crypto : null,
      );
      if (!readable) {
        debugPrint(
          '[mutande.mail] mailbox.db unreadable with current key — recreating',
        );
        await wipeMailboxFiles(paths);
      }
    }

    final executor = LazyDatabase(() async {
      if (wantEncrypt) {
        return NativeDatabase.createInBackground(
          file,
          setup: (rawDb) {
            // Compatibility before key when opening existing SQLCipher DBs.
            rawDb.execute('PRAGMA cipher_compatibility = 4;');
            rawDb.execute("PRAGMA key = \"x'${crypto.sqlCipherHexKey}'\";");
            rawDb.execute('PRAGMA foreign_keys = ON;');
          },
        );
      }
      return NativeDatabase.createInBackground(
        file,
        setup: (rawDb) {
          rawDb.execute('PRAGMA foreign_keys = ON;');
        },
      );
    });

    final db = MailboxDatabase(executor);
    // Eager open so wrong-key / corrupt files fail here, not on first UI query.
    try {
      await db.customSelect('SELECT 1').get();
    } catch (e) {
      await db.close();
      if (!alreadyRecreated && _looksLikeUnreadableDb(e)) {
        debugPrint(
          '[mutande.mail] mailbox ensureOpen failed ($e) — recreating',
        );
        await wipeMailboxFiles(paths);
        return open(
          paths: paths,
          crypto: crypto,
          encrypt: encrypt,
          requireSqlCipher: requireSqlCipher,
          alreadyRecreated: true,
        );
      }
      rethrow;
    }
    return db;
  }

  /// Delete `mailbox.db` and sidecar `-wal` / `-shm` files.
  static Future<void> deleteDbFiles(String dbPath) async {
    for (final path in [
      dbPath,
      '$dbPath-wal',
      '$dbPath-shm',
      '$dbPath-journal',
    ]) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Drop DB + encrypted media/preview after a key mismatch or corrupt file.
  static Future<void> wipeMailboxFiles(MailboxPaths paths) async {
    await deleteDbFiles(paths.dbPath);
    await _wipeDirContents(paths.mediaDir);
    await _wipeDirContents(paths.previewDir);
  }

  /// In-memory DB for unit tests (no disk, no SQLCipher).
  static MailboxDatabase memory() {
    return MailboxDatabase(NativeDatabase.memory());
  }
}

bool get _usePlainSqlite {
  if (kIsWeb) return true;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
  return false;
}

/// Fail closed if hooks did not link SQLCipher — stock SQLite ignores PRAGMA key.
Future<void> _assertSqlCipherLinked(MailboxCrypto crypto) async {
  final dir = await Directory.systemTemp.createTemp('mutande-sqlcipher-probe-');
  final path = p.join(dir.path, 'probe.db');
  Database? probe;
  try {
    final hex = crypto.sqlCipherHexKey;
    // Wrong key: flip first byte.
    final wrongHex = StringBuffer();
    final first = int.parse(hex.substring(0, 2), radix: 16) ^ 0xff;
    wrongHex.write(first.toRadixString(16).padLeft(2, '0'));
    wrongHex.write(hex.substring(2));

    probe = sqlite3.open(path);
    probe.execute('PRAGMA cipher_compatibility = 4;');
    probe.execute("PRAGMA key = \"x'$hex'\";");
    probe.execute('CREATE TABLE _mutande_probe (id INTEGER);');
    probe.execute('INSERT INTO _mutande_probe VALUES (1);');
    probe.execute('SELECT count(*) FROM _mutande_probe;');
    probe.close();
    probe = null;

    // Re-open with wrong key — SQLCipher must refuse; stock SQLite would succeed.
    probe = sqlite3.open(path);
    probe.execute('PRAGMA cipher_compatibility = 4;');
    probe.execute("PRAGMA key = \"x'$wrongHex'\";");
    try {
      probe.execute('SELECT count(*) FROM _mutande_probe;');
      throw MailboxEncryptionException(
        'Linked SQLite is not SQLCipher — refusing plaintext mailbox',
      );
    } on MailboxEncryptionException {
      rethrow;
    } catch (_) {
      // Expected: wrong key / not a database.
    }
  } on MailboxEncryptionException {
    rethrow;
  } catch (e) {
    throw MailboxEncryptionException(
      'SQLCipher probe failed — refusing mailbox open: $e',
    );
  } finally {
    probe?.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

bool _looksLikeUnreadableDb(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('file is not a database') ||
      s.contains('sqliteexception(26)') ||
      s.contains('code 26');
}

Future<void> _wipeDirContents(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return;
  try {
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {}
}

/// True when [dbPath] opens and answers a trivial query with [crypto] (or plain).
Future<bool> _dbReadableWithKey(String dbPath, MailboxCrypto? crypto) async {
  Database? db;
  try {
    db = sqlite3.open(dbPath);
    if (crypto != null) {
      db.execute('PRAGMA cipher_compatibility = 4;');
      db.execute("PRAGMA key = \"x'${crypto.sqlCipherHexKey}'\";");
    }
    db.select('SELECT count(*) FROM sqlite_master;');
    return true;
  } catch (_) {
    return false;
  } finally {
    db?.close();
  }
}
