import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../daemon_client.dart';
import 'mailbox_crypto.dart';
import 'mailbox_paths.dart';

/// Result of ingesting one resource into the encrypted media dir.
class IngestedResource {
  const IngestedResource({
    required this.resource,
    required this.sha256,
    required this.encryptedPath,
    required this.createdNew,
  });

  final BundleResourceView resource;
  final String sha256;
  final String encryptedPath;
  final bool createdNew;
}

/// Encrypts core `blob_cache` / inline content into the app media dir.
class MailboxMediaStore {
  MailboxMediaStore({
    required this.paths,
    required this.crypto,
  });

  final MailboxPaths paths;
  final MailboxCrypto crypto;

  static const _uuid = Uuid();

  /// Lookup existing media id by content hash (caller supplies from DB).
  Future<String?> Function(String sha256)? findMediaIdBySha;

  /// Ingest resources on a detail: copy plaintext into encrypted media files.
  /// Returns a detail whose resources point at [mediaId] (no core paths),
  /// plus ingest metadata for the media table.
  Future<({ThreadDetailResult detail, List<IngestedResource> ingested})>
  ingestThreadDetail(ThreadDetailResult detail) async {
    await paths.ensureDirs();
    final messages = <ThreadMessageView>[];
    final ingested = <IngestedResource>[];
    for (final msg in detail.messages) {
      final resources = <BundleResourceView>[];
      for (final r in msg.resources) {
        final result = await _ingestResource(
          r,
          threadId: detail.id,
          messageId: msg.id,
        );
        resources.add(result.resource);
        if (result.sha256.isNotEmpty) {
          ingested.add(result);
        }
      }
      messages.add(
        ThreadMessageView(
          id: msg.id,
          fromHandle: msg.fromHandle,
          createdAt: msg.createdAt,
          parentMessageId: msg.parentMessageId,
          inReplyTo: msg.inReplyTo,
          bundleSubject: msg.bundleSubject,
          bundleNotes: msg.bundleNotes,
          pingKind: msg.pingKind,
          hasHandshake: msg.hasHandshake,
          handshake: msg.handshake,
          questionPrompts: msg.questionPrompts,
          resourceRequests: msg.resourceRequests,
          resources: resources,
          answerTexts: msg.answerTexts,
          openError: msg.openError,
          upvotes: msg.upvotes,
        ),
      );
    }
    return (
      detail: detail.copyWith(messages: messages),
      ingested: ingested,
    );
  }

  Future<IngestedResource> _ingestResource(
    BundleResourceView r, {
    required String threadId,
    required String messageId,
  }) async {
    if (r.mediaId != null && r.mediaId!.trim().isNotEmpty) {
      final mid = r.mediaId!.trim();
      return IngestedResource(
        resource: r.copyWith(clearPath: true, clearContent: true),
        sha256: '',
        encryptedPath: p.join(paths.mediaDir, '$mid.enc'),
        createdNew: false,
      );
    }

    Uint8List? bytes;
    if (r.hasPath) {
      final file = File(r.path!.trim());
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      }
    }
    if (bytes == null && r.hasContent) {
      bytes = Uint8List.fromList(utf8.encode(r.content!));
    }
    if (bytes == null || bytes.isEmpty) {
      return IngestedResource(
        resource: r,
        sha256: '',
        encryptedPath: '',
        createdNew: false,
      );
    }

    final digest = hashBytes(bytes);
    final existingId = findMediaIdBySha == null
        ? null
        : await findMediaIdBySha!(digest);
    if (existingId != null && existingId.isNotEmpty) {
      final encPath = p.join(paths.mediaDir, '$existingId.enc');
      if (await File(encPath).exists()) {
        return IngestedResource(
          resource: r.copyWith(
            mediaId: existingId,
            size: bytes.length,
            clearPath: true,
            clearContent: true,
          ),
          sha256: digest,
          encryptedPath: encPath,
          createdNew: false,
        );
      }
    }

    final mediaId = _uuid.v4();
    final encPath = p.join(paths.mediaDir, '$mediaId.enc');
    final sealed = await crypto.encrypt(bytes);
    await File(encPath).writeAsBytes(sealed, flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', encPath]);
      } catch (_) {}
    }

    return IngestedResource(
      resource: r.copyWith(
        mediaId: mediaId,
        size: bytes.length,
        clearPath: true,
        clearContent: true,
      ),
      sha256: digest,
      encryptedPath: encPath,
      createdNew: true,
    );
  }

  /// Decrypt [mediaId] into the preview cache; returns plaintext path.
  Future<String?> materializePreview({
    required String mediaId,
    required String name,
    String? encryptedPath,
  }) async {
    await paths.ensureDirs();
    final enc = encryptedPath ?? p.join(paths.mediaDir, '$mediaId.enc');
    final encFile = File(enc);
    if (!await encFile.exists()) return null;

    final sealed = await encFile.readAsBytes();
    final plain = await crypto.decrypt(sealed);
    final safe = name.replaceAll(RegExp(r'[/\\]'), '_').trim();
    final fileName = safe.isEmpty ? mediaId : safe;
    final previewPath = p.join(paths.previewDir, mediaId, fileName);
    final preview = File(previewPath);
    await preview.parent.create(recursive: true);
    await preview.writeAsBytes(plain, flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['700', preview.parent.path]);
        await Process.run('chmod', ['600', previewPath]);
      } catch (_) {}
    }
    return previewPath;
  }

  Future<void> clearPreviewsForMediaIds(Iterable<String> mediaIds) async {
    for (final mid in mediaIds) {
      if (mid.trim().isEmpty) continue;
      final preview = Directory(p.join(paths.previewDir, mid.trim()));
      if (await preview.exists()) {
        await preview.delete(recursive: true);
      }
    }
  }

  Future<void> clearAllPreviews() async {
    final dir = Directory(paths.previewDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> deleteEncrypted(String mediaId) async {
    final enc = File(p.join(paths.mediaDir, '$mediaId.enc'));
    if (await enc.exists()) {
      await enc.delete();
    }
    final preview = Directory(p.join(paths.previewDir, mediaId));
    if (await preview.exists()) {
      await preview.delete(recursive: true);
    }
  }

  /// Content hash of plaintext (for dedupe / media table).
  static String hashBytes(Uint8List bytes) => sha256.convert(bytes).toString();
}
