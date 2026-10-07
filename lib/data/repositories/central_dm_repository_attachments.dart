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
  /// success `data` is an [UploadedBlob]. Always encrypted: central's files
  /// stop at 10 MB, well under where sending one unencrypted is offered.
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
      final UploadedBlob uploaded = (
        path: path,
        keyB64: blob.keyB64,
        nonceB64: blob.nonceB64,
        sha256B64: null,
        chunkSize: null,
      );
      return APIResponse.success(uploaded);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Remove attachment blobs — what a client does when it deletes a message
  /// that carried them.
  ///
  /// Central has no retention sweep for these, so this is the *only* thing that
  /// ever frees them: unlike a self-hosted server, nothing here runs later to
  /// collect what a failed delete left behind. Central's own 30-day message TTL
  /// doesn't touch storage. Best-effort all the same — see
  /// [AttachmentCleanup.forMessage] for why a blob must never block a delete.
  Future<APIResponse> deleteAttachments(List<String> paths) async {
    if (paths.isEmpty) return APIResponse.success({'deleted': 0});
    try {
      await _client.storage.from(_attachmentsBucket).remove(paths);
      return APIResponse.success({'deleted': paths.length});
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Download + open one attachment blob. On success `data` is the file's
  /// `Uint8List`. Opens a plain one too, though this client never sends one
  /// here: what arrives is whatever the other end sent.
  Future<APIResponse> downloadAttachment({
    required String path,
    required String keyB64,
    required String nonceB64,
    String? sha256B64,
    int? chunkSize,
  }) async {
    try {
      final bytes = await _client.storage
          .from(_attachmentsBucket)
          .download(path);
      final clear = await _attachments.open(
        ciphertext: bytes,
        keyB64: keyB64,
        nonceB64: nonceB64,
        sha256B64: sha256B64,
        chunkSize: chunkSize,
      );
      return APIResponse.success(clear);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
