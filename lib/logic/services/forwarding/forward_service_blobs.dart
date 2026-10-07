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

  /// Fetch and open every attachment once, whatever it is being forwarded to.
  ///
  /// [files] is parallel to the attachment list, with null where the fetch
  /// failed — one unreadable blob costs its own thumbnail, not the whole
  /// forward. A small file comes back in memory; a big one is written to a
  /// scratch file a piece at a time, listed in [scratch] for the caller to
  /// remove once every destination has it.
  Future<({List<PendingAttachment?> files, List<ScratchSink> scratch})>
  _fetchBlobs(List<Attachment> attachments, String? sourceServerId) async {
    final files = <PendingAttachment?>[];
    final scratch = <ScratchSink>[];
    for (final attachment in attachments) {
      try {
        // No server id means it came from central, which keeps its own
        // bucket and its own client, and whose files are all small.
        if (sourceServerId != null &&
            attachment.size > AttachmentStaging.inMemoryMaxBytes) {
          final sink = await scratchTarget(attachment.name);
          final response = await servers.saveAttachment(
            attachment: attachment,
            sink: sink,
            serverId: sourceServerId,
          );
          if (!response.success) {
            files.add(null);
            continue;
          }
          scratch.add(sink);
          files.add(
            PendingAttachment.file(
              file: sink.file,
              size: attachment.size,
              name: attachment.name,
              mime: attachment.mime,
              kind: attachment.kind,
              width: attachment.width,
              height: attachment.height,
              durationMs: attachment.durationMs,
            ),
          );
          continue;
        }
        final response = sourceServerId == null
            ? await central.downloadAttachment(
                path: attachment.storagePath,
                keyB64: attachment.keyB64,
                nonceB64: attachment.nonceB64,
                sha256B64: attachment.sha256B64,
                chunkSize: attachment.chunkSize,
              )
            : await servers.downloadAttachment(
                path: attachment.storagePath,
                keyB64: attachment.keyB64,
                nonceB64: attachment.nonceB64,
                sha256B64: attachment.sha256B64,
                chunkSize: attachment.chunkSize,
                serverId: sourceServerId,
              );
        final bytes = response.success ? response.data as Uint8List? : null;
        files.add(
          bytes == null
              ? null
              : PendingAttachment(
                  bytes: bytes,
                  name: attachment.name,
                  mime: attachment.mime,
                  kind: attachment.kind,
                  width: attachment.width,
                  height: attachment.height,
                  durationMs: attachment.durationMs,
                ),
        );
      } catch (e) {
        HelperMethods.printDebug('[Forward] blob fetch failed: $e');
        files.add(null);
      }
    }
    return (files: files, scratch: scratch);
  }

  /// Re-encrypt and upload into one destination, answering with the
  /// attachments as that destination will see them.
  ///
  /// A fresh key per copy, because the upload generates one — which is also
  /// the right answer: the audience is different, and the original's key
  /// should not be the thing standing between them and the file. A file sent
  /// unencrypted is encrypted here too: whoever chose to expose it chose for
  /// that server, not this one.
  ///
  /// [serverId] null uploads to central. [plain] sends every file as it is,
  /// for a channel whose encryption is off.
  Future<List<Attachment>> _reupload(
    List<Attachment> attachments,
    List<PendingAttachment?> files, {
    required String scopePrefix,
    String? serverId,
    bool plain = false,
  }) async {
    final out = <Attachment>[];
    for (var i = 0; i < attachments.length; i++) {
      final file = i < files.length ? files[i] : null;
      if (file == null) continue;
      try {
        final response = serverId == null
            ? await central.uploadAttachment(
                scopePrefix: scopePrefix,
                data: file.bytes ?? await file.source.readAsBytes(),
              )
            : await servers.uploadStaged(
                file,
                scopePrefix: scopePrefix,
                serverId: serverId,
                plain: plain,
              );
        if (!response.success) continue;
        final blob = response.data as UploadedBlob;
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
            sha256B64: blob.sha256B64,
            chunkSize: blob.chunkSize,
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
