part of 'forward_service.dart';

/// Moving a forwarded message's attachment bytes into the destination.
///
/// **The blob is copied, never pointed at**, and there are two independent
/// reasons either of which would be enough. Each server keeps its own
/// bucket (`chat-<server id>`), so a path into the source is a path the
/// readers cannot open. And the sweep that clears orphaned objects works off
/// the oldest surviving message *per scope* (`app.orphaned_attachments`), so
/// a shared object would be deleted the moment the original's channel
/// trimmed past it — leaving a forward that rendered correctly for a week
/// and then quietly lost its picture.
mixin _ForwardBlobsMixin {
  ServerCubit get servers;
  CentralDmRepository get central;

  /// Decrypt every attachment once, whatever it is being forwarded to.
  ///
  /// Parallel to the attachment list, with null where the fetch failed — one
  /// unreadable blob costs its own thumbnail, not the whole forward.
  Future<List<Uint8List?>> _fetchBlobs(
    List<Attachment> attachments,
    String? sourceServerId,
  ) async {
    final out = <Uint8List?>[];
    for (final attachment in attachments) {
      try {
        // No server id means it came from central, which keeps its own
        // bucket and its own client.
        final response = sourceServerId == null
            ? await central.downloadAttachment(
                path: attachment.storagePath,
                keyB64: attachment.keyB64,
                nonceB64: attachment.nonceB64,
              )
            : await servers.downloadAttachment(
                path: attachment.storagePath,
                keyB64: attachment.keyB64,
                nonceB64: attachment.nonceB64,
                serverId: sourceServerId,
              );
        out.add(response.success ? response.data as Uint8List? : null);
      } catch (e) {
        HelperMethods.printDebug('[Forward] blob fetch failed: $e');
        out.add(null);
      }
    }
    return out;
  }

  /// Re-encrypt and upload into one destination, answering with the
  /// attachments as that destination will see them.
  ///
  /// A fresh key per copy, because the upload generates one — which is also
  /// the right answer: the audience is different, and the original's key
  /// should not be the thing standing between them and the file.
  ///
  /// [serverId] null uploads to central.
  Future<List<Attachment>> _reupload(
    List<Attachment> attachments,
    List<Uint8List?> bytes, {
    required String scopePrefix,
    String? serverId,
  }) async {
    final out = <Attachment>[];
    for (var i = 0; i < attachments.length; i++) {
      final data = i < bytes.length ? bytes[i] : null;
      if (data == null) continue;
      try {
        final response = serverId == null
            ? await central.uploadAttachment(
                scopePrefix: scopePrefix,
                data: data,
              )
            : await servers.uploadAttachment(
                scopePrefix: scopePrefix,
                data: data,
                serverId: serverId,
              );
        if (!response.success) continue;
        final blob =
            response.data as ({String path, String keyB64, String nonceB64});
        final source = attachments[i];
        out.add(
          Attachment(
            id: source.id,
            kind: source.kind,
            name: source.name,
            mime: source.mime,
            size: source.size,
            storagePath: blob.path,
            keyB64: blob.keyB64,
            nonceB64: blob.nonceB64,
            width: source.width,
            height: source.height,
            durationMs: source.durationMs,
          ),
        );
      } catch (e) {
        HelperMethods.printDebug('[Forward] blob upload failed: $e');
      }
    }
    return out;
  }
}
