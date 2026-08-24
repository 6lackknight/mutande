import 'dart:async';

import '../services/daemon_event_client.dart';
import '../services/mailbox/mailbox_store.dart';
import '../util/mail_trace.dart';
import 'collab_repository.dart';
import 'network_repository.dart';
import 'thread_repository.dart';

/// Live sync status for quiet chrome (not a blocking spinner).
class SyncStatus {
  const SyncStatus({
    this.lastRevision = 0,
    this.decryptInFlight = 0,
    this.syncing = false,
    this.lastError,
  });

  final int lastRevision;
  final int decryptInFlight;
  final bool syncing;
  final String? lastError;

  SyncStatus copyWith({
    int? lastRevision,
    int? decryptInFlight,
    bool? syncing,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncStatus(
      lastRevision: lastRevision ?? this.lastRevision,
      decryptInFlight: decryptInFlight ?? this.decryptInFlight,
      syncing: syncing ?? this.syncing,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Coalesces `inbox_changed` → list refresh → eager decrypt write-through.
///
/// UI opens read the mailbox; this path decrypts on receive so opens don't wait.
class SyncCoordinator {
  SyncCoordinator({
    required this.threads,
    required this.collabs,
    required this.network,
    this.events,
    this.maxConcurrentDecrypts = 4,
    this.myHandle,
  });

  final ThreadRepository threads;
  final CollabRepository collabs;
  final NetworkRepository network;
  final DaemonEventClient? events;
  final int maxConcurrentDecrypts;
  final String? myHandle;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusChanges => _statusController.stream;

  StreamSubscription<InboxChangedEvent>? _sub;
  bool _syncInFlight = false;
  bool _syncPending = false;
  bool _started = false;

  void _setStatus(SyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  /// Start listening to inbox WebSocket (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    MailTrace.event(
      'sync.start',
      fields: {
        'events': events != null,
        'mailbox': MailboxStore.instance != null,
        'handle': myHandle,
      },
    );
    final ev = events;
    if (ev == null) {
      MailTrace.event('sync.start skipped — no DaemonEventClient');
      return;
    }
    _sub = ev.events.listen((e) {
      MailTrace.event(
        'sync.inbox_changed',
        fields: {'revision': e.revision},
      );
      unawaited(syncAll(revision: e.revision));
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _statusController.close();
  }

  /// Full sync: threads + collabs + network. Coalesces overlapping calls.
  Future<void> syncAll({int? revision}) async {
    if (_syncInFlight) {
      _syncPending = true;
      MailTrace.event('sync.coalesce pending=true');
      return;
    }
    _syncInFlight = true;
    final sw = MailTrace.start('sync.all revision=${revision ?? _status.lastRevision}');
    _setStatus(
      _status.copyWith(
        syncing: true,
        lastRevision: revision ?? _status.lastRevision,
        clearError: true,
      ),
    );
    try {
      await Future.wait([
        syncThreads(),
        syncCollabs(),
        syncNetwork(),
      ]);
      MailTrace.end(sw, 'sync.all', fields: {'ok': true});
    } catch (e) {
      _setStatus(_status.copyWith(lastError: e.toString(), syncing: false));
      MailTrace.end(sw, 'sync.all', fields: {'error': '$e'});
    } finally {
      _syncInFlight = false;
      _setStatus(_status.copyWith(syncing: false));
      if (_syncPending) {
        _syncPending = false;
        unawaited(syncAll());
      }
    }
  }

  /// List threads then decrypt any new/stale details into the mailbox.
  Future<void> syncThreads({String filter = 'all'}) async {
    final sw = MailTrace.start('sync.threads filter=$filter');
    var ingested = 0;
    final list = await threads.refreshList(filter: filter);
    await _mapPool(list, (t) async {
      try {
        final did = await threads.ingestIfStale(
          threadId: t.id,
          listUpdatedAt: t.updatedAt,
        );
        if (did) ingested++;
      } catch (_) {}
    });
    MailTrace.end(
      sw,
      'sync.threads',
      fields: {'listed': list.length, 'ingested': ingested},
    );
  }

  Future<void> syncCollabs() async {
    final sw = MailTrace.start('sync.collabs');
    try {
      var ingested = 0;
      final listed = await collabs.refreshList(archived: false);
      await _mapPool(listed.collabs, (c) async {
        try {
          final did = await collabs.ingestIfStale(
            collabId: c.id,
            listUpdatedAt: c.updatedAt,
          );
          if (did) ingested++;
        } catch (_) {}
      });
      MailTrace.end(
        sw,
        'sync.collabs',
        fields: {'listed': listed.collabs.length, 'ingested': ingested},
      );
    } catch (e) {
      MailTrace.end(sw, 'sync.collabs', fields: {'error': '$e'});
    }
  }

  Future<void> syncNetwork() async {
    final sw = MailTrace.start('sync.network');
    try {
      await network.refreshPeople();
      await network.refreshAgents(handle: myHandle);
      MailTrace.end(sw, 'sync.network', fields: {'ok': true});
    } catch (e) {
      MailTrace.end(sw, 'sync.network', fields: {'error': '$e'});
    }
  }

  /// Run [work] over [items] with bounded concurrency.
  Future<void> _mapPool<T>(
    List<T> items,
    Future<void> Function(T item) work,
  ) async {
    if (items.isEmpty) return;
    var next = 0;
    var inFlight = 0;
    final done = Completer<void>();
    var remaining = items.length;

    void schedule() {
      while (inFlight < maxConcurrentDecrypts && next < items.length) {
        final item = items[next++];
        inFlight++;
        _setStatus(_status.copyWith(decryptInFlight: inFlight));
        unawaited(() async {
          try {
            await work(item);
          } finally {
            inFlight--;
            remaining--;
            _setStatus(_status.copyWith(decryptInFlight: inFlight));
            if (remaining == 0) {
              if (!done.isCompleted) done.complete();
            } else {
              schedule();
            }
          }
        }());
      }
    }

    schedule();
    await done.future;
  }
}
