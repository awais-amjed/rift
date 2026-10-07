import 'dart:typed_data';

import '../../data/classes/api_response.dart';
import '../../data/classes/attachment.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/blob/blob_sink.dart';

/// How a chat draws and saves the attachments in it, handed down from the
/// cubit that owns the conversation.
///
/// Called like a function for the bytes of one being drawn (from the
/// in-memory cache or a download; null on failure). [save] is the other road,
/// for a file being saved: its bytes go to a [BlobSink] as they are opened,
/// so a file bigger than memory is never held whole.
///
/// Equal when built from the same two functions. Cubits hand one out from a
/// getter, so every rebuild of a chat makes a new one; a thumbnail compares
/// the old against the new to decide whether to fetch again, and by identity
/// every rebuild refetched and flashed the placeholder over the picture.
class AttachmentLoader {
  final Future<Uint8List?> Function(Attachment attachment) load;
  final Future<APIResponse> Function(
    Attachment attachment,
    BlobSink sink, {
    TransferProgress? onProgress,
  })
  save;

  const AttachmentLoader({required this.load, required this.save});

  Future<Uint8List?> call(Attachment attachment) => load(attachment);

  @override
  bool operator ==(Object other) =>
      other is AttachmentLoader && other.load == load && other.save == save;

  @override
  int get hashCode => Object.hash(load, save);
}
