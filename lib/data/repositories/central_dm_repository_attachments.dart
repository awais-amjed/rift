part of 'central_dm_repository.dart';

/// Attachment blobs for central DMs. Bytes are encrypted with a fresh
/// per-file key before they leave the device and land in the caller's own
/// storage folder, so the central server stores only opaque blobs — the key
/// travels inside the encrypted message body, never to the server.
mixin _CentralDmAttachmentsMixin {
  SupabaseClient get _client;
  AttachmentRepository get _attachments;

  static const String _attachmentsBucket = 'central-dm-attachments';

  // ──────────────────────────────────────────────────────────
  // Attachments (E2E-encrypted blobs in central storage)
  // ──────────────────────────────────────────────────────────

  /// Encrypt + upload one attachment blob into the caller's own folder. On
  /// success `data` is `({String path, String keyB64, String nonceB64})`.
  Future<APIResponse> uploadAttachment({
    required String scopePrefix,
    required Uint8List data,
  }) async {
    try {
      final blob = await _attachments.seal(data);
      final path = AttachmentRepository.buildPath(scopePrefix);
      await _client.storage
          .from(_attachmentsBucket)
          .uploadBinary(
            path,
            blob.ciphertext,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
              upsert: false,
            ),
          );
      return APIResponse.success((
        path: path,
        keyB64: blob.keyB64,
        nonceB64: blob.nonceB64,
      ));
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Download + decrypt one attachment blob. On success `data` is the decrypted
  /// `Uint8List`.
  Future<APIResponse> downloadAttachment({
    required String path,
    required String keyB64,
    required String nonceB64,
  }) async {
    try {
      final bytes = await _client.storage
          .from(_attachmentsBucket)
          .download(path);
      final clear = await _attachments.open(
        ciphertext: bytes,
        keyB64: keyB64,
        nonceB64: nonceB64,
      );
      return APIResponse.success(clear);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
