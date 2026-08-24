import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../services/daemon_client.dart';
import '../services/daemon_event_client.dart';
import '../services/mailbox/mailbox_store.dart';
import '../repositories/collab_repository.dart';
import '../repositories/network_repository.dart';
import '../repositories/sync_coordinator.dart';
import '../repositories/thread_repository.dart';

/// Bumped after mailbox write-through so list/detail providers re-read DB.
final mailEpochProvider = StateProvider<int>((ref) => 0);

final daemonClientProvider = Provider<DaemonClient>((ref) {
  throw UnimplementedError('Override daemonClientProvider at ProviderScope');
});

final daemonEventClientProvider = Provider<DaemonEventClient?>((ref) => null);

final mailboxStoreProvider = Provider<MailboxStore?>((ref) {
  return MailboxStore.instance;
});

final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ThreadRepository(
    daemon: ref.watch(daemonClientProvider),
    mailbox: () => MailboxStore.instance,
    onMailboxChanged: () {
      ref.read(mailEpochProvider.notifier).state++;
    },
  );
});

final collabRepositoryProvider = Provider<CollabRepository>((ref) {
  return CollabRepository(
    daemon: ref.watch(daemonClientProvider),
    mailbox: () => MailboxStore.instance,
    onMailboxChanged: () {
      ref.read(mailEpochProvider.notifier).state++;
    },
  );
});

final networkRepositoryProvider = Provider<NetworkRepository>((ref) {
  return NetworkRepository(
    daemon: ref.watch(daemonClientProvider),
    mailbox: () => MailboxStore.instance,
    onMailboxChanged: () {
      ref.read(mailEpochProvider.notifier).state++;
    },
  );
});

/// Session handle for peer-agent hydration (optional).
final sessionHandleProvider = Provider<String?>((ref) => null);

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final sync = SyncCoordinator(
    threads: ref.watch(threadRepositoryProvider),
    collabs: ref.watch(collabRepositoryProvider),
    network: ref.watch(networkRepositoryProvider),
    events: ref.watch(daemonEventClientProvider),
    myHandle: ref.watch(sessionHandleProvider),
  );
  ref.onDispose(() {
    unawaited(sync.dispose());
  });
  return sync;
});

/// Quiet sync chrome — revision / in-flight decrypts.
final syncStatusProvider = Provider<SyncStatus>((ref) {
  return ref.watch(syncCoordinatorProvider).status;
});
