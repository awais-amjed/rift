import 'dart:math';
import 'dart:typed_data';

import '../../data/classes/api_response.dart';
import '../../data/classes/attachment.dart';
import '../../data/classes/link_preview.dart';
import '../../data/classes/pending_attachment.dart';
import '../../data/repositories/attachment_repository.dart';
import 'attachment_cache.dart';
import 'link_preview_fetcher.dart';

/// Uploads one blob: encrypted, or as it is when [plain]. Answers an
/// [APIResponse] whose `data` is an [UploadedBlob] on success.
typedef BlobUpload = Future<APIResponse> Function(Uint8List data, {bool plain});

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
  /// [uploadOne] receives the raw bytes and whether the sender chose to send
  /// them unencrypted.
  /// The sender's link preview with its thumbnail uploaded, or null when
  /// there was none. The words travel in the body; only the picture needs
  /// a blob, and it takes the same encrypted road as any attachment.
  ///
  /// [preview] may still be fetching — a link sent before its card was
  /// ready — so this is where the send waits for it, after the pending row
  /// is already on screen.
  static Future<LinkPreview?> uploadPreview({
    required Future<PendingLinkPreview?>? preview,
    required BlobUpload uploadOne,
  }) async {
    final pending = await preview;
    if (pending == null) return null;
    final image = pending.image;
    final uploaded = image == null
        ? const <Attachment>[]
        : await uploadAll(pending: [image], uploadOne: uploadOne);
    return LinkPreview(
      url: pending.url,
      title: pending.title,
      description: pending.description,
      siteName: pending.siteName,
      image: uploaded.isEmpty ? null : uploaded.first,
    );
  }

  static Future<List<Attachment>> uploadAll({
    required List<PendingAttachment> pending,
    required BlobUpload uploadOne,
  }) async {
    final result = <Attachment>[];
    for (final pa in pending) {
      final response = await uploadOne(pa.bytes, plain: pa.plain);
      if (!response.success || response.data == null) {
        throw AttachmentUploadException(
          response.error ?? 'Attachment upload failed',
          errorCode: response.errorCode,
        );
      }
      final r = response.data as UploadedBlob;
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
          sha256B64: r.sha256B64,
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

/// An attachment that did not upload, and the code that says whether trying
/// again could help.
class AttachmentUploadException implements Exception {
  final String message;

  /// The code the failed upload came back with, so a caller can tell a
  /// connection that dropped from a file the server refused. Null when the
  /// response carried none. See `ErrorCode.isRetryable`.
  final String? errorCode;

  AttachmentUploadException(this.message, {this.errorCode});
  @override
  String toString() => message;
}
