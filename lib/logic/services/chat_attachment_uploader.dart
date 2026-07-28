import 'dart:math';
import 'dart:typed_data';

import '../../data/classes/api_response.dart';
import '../../data/classes/attachment.dart';
import '../../data/classes/pending_attachment.dart';
import 'attachment_cache.dart';

/// Shared "upload staged files → attachment metadata" step used by all three
/// chat pipelines (channels, server DMs, central DMs). The only thing that
/// differs between them is *how* a single blob is uploaded, so that's passed in
/// as [uploadOne] (self-hosted Storage REST vs. the central Supabase SDK).
class ChatAttachmentUploader {
  static final _rng = Random.secure();

  static String _attachmentId() => List.generate(
    8,
    (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Uploads every [pending] file in order and returns the resulting
  /// [Attachment]s. Each uploaded blob's plaintext bytes are stashed in the
  /// [AttachmentCache] under its storage path so the sender renders it without
  /// a round-trip. Throws [AttachmentUploadException] on the first failure.
  ///
  /// [uploadOne] receives the raw bytes and must return an [APIResponse] whose
  /// `data` is `({String path, String keyB64, String nonceB64})` on success.
  static Future<List<Attachment>> uploadAll({
    required List<PendingAttachment> pending,
    required Future<APIResponse> Function(Uint8List data) uploadOne,
  }) async {
    final result = <Attachment>[];
    for (final pa in pending) {
      final response = await uploadOne(pa.bytes);
      if (!response.success || response.data == null) {
        throw AttachmentUploadException(
          response.error ?? 'Attachment upload failed',
        );
      }
      final r =
          response.data as ({String path, String keyB64, String nonceB64});
      AttachmentCache.instance.put(r.path, pa.bytes);
      result.add(
        Attachment(
          id: _attachmentId(),
          kind: pa.kind,
          name: pa.name,
          mime: pa.mime,
          size: pa.size,
          storagePath: r.path,
          keyB64: r.keyB64,
          nonceB64: r.nonceB64,
          width: pa.width,
          height: pa.height,
          durationMs: pa.durationMs,
        ),
      );
    }
    return result;
  }

  /// Return an attachment's decrypted bytes, from the [AttachmentCache] if
  /// present, else by invoking [download] (an [APIResponse] whose `data` is the
  /// decrypted `Uint8List`) and caching the result. Null on failure.
  static Future<Uint8List?> load({
    required Attachment attachment,
    required Future<APIResponse> Function() download,
  }) async {
    final cached = AttachmentCache.instance.get(attachment.storagePath);
    if (cached != null) return cached;
    final response = await download();
    if (!response.success || response.data == null) return null;
    final bytes = response.data as Uint8List;
    AttachmentCache.instance.put(attachment.storagePath, bytes);
    return bytes;
  }
}

class AttachmentUploadException implements Exception {
  final String message;
  AttachmentUploadException(this.message);
  @override
  String toString() => message;
}
