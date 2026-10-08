import 'dart:math';
import 'dart:typed_data';

import '../../data/classes/api_response.dart';
import '../../data/classes/attachment.dart';
import '../../data/classes/link_preview.dart';
import '../../data/classes/pending_attachment.dart';
import '../../data/repositories/attachment_repository.dart';
import 'link_preview_fetcher.dart';
import 'media_store.dart';

/// Uploads one staged file — encrypted, or as it is when the sender chose
/// `plain` — reporting [onProgress] as a big one goes. Answers an
/// [APIResponse] whose `data` is an [UploadedBlob] on success.
typedef BlobUpload =
    Future<APIResponse> Function(
      PendingAttachment file, {
      TransferProgress? onProgress,
    });

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

  /// Uploads every [pending] file in order and returns the resulting
  /// [Attachment]s. A small file's plaintext bytes are stashed in the
  /// [MediaStore.attachments] under its storage path so the sender renders it without
  /// a round-trip. Throws [AttachmentUploadException] on the first failure.
  ///
  /// [onProgress] hears how much of all of [pending] has gone, 0 to 1, in
  /// steps of at least a percent — often enough for a bar, rarely enough not
  /// to redraw a chat list for every request.
  static Future<List<Attachment>> uploadAll({
    required List<PendingAttachment> pending,
    required BlobUpload uploadOne,
    void Function(double progress)? onProgress,
  }) async {
    final result = <Attachment>[];
    final total = pending.fold(0, (sum, a) => sum + a.size);
    var before = 0;
    var told = 0.0;
    void tell(int done) {
      if (onProgress == null || total == 0) return;
      final progress = (before + done) / total;
      if (progress - told < 0.01 && progress < 1) return;
      told = progress;
      onProgress(progress.clamp(0, 1).toDouble());
    }

    for (final pa in pending) {
      final response = await uploadOne(
        pa,
        // What went over the wire, scaled to the file: a sealed file is a
        // little bigger than the one it came from.
        onProgress: (done, all) =>
            tell(all == 0 ? pa.size : (pa.size * done / all).round()),
      );
      before += pa.size;
      tell(0);
      if (!response.success || response.data == null) {
        throw AttachmentUploadException(
          response.error ?? 'Attachment upload failed',
          errorCode: response.errorCode,
        );
      }
      final r = response.data as UploadedBlob;
      // A big file is not held, so there is nothing to keep; the sender's
      // card fetches it like anyone else's if it is ever opened.
      if (pa.bytes case final bytes?) {
        MediaStore.attachments.put(r.path, bytes);
      }
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
          chunkSize: r.chunkSize,
          width: pa.width,
          height: pa.height,
          durationMs: pa.durationMs,
        ),
      );
    }
    return result;
  }

  /// Return an attachment's decrypted bytes, from [MediaStore.attachments] if
  /// held, else by invoking [download] (an [APIResponse] whose `data` is the
  /// decrypted `Uint8List`). Null on failure. Two callers asking at once share
  /// one download.
  static Future<Uint8List?> load({
    required Attachment attachment,
    required Future<APIResponse> Function() download,
  }) => MediaStore.attachments.load(attachment.storagePath, () async {
    final response = await download();
    if (!response.success || response.data == null) return null;
    return response.data as Uint8List;
  });
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
