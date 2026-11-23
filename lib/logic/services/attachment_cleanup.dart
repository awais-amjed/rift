import '../../data/classes/api_response.dart';
import '../../data/classes/attachment.dart';
import '../../data/classes/chat_message.dart';
import '../helper_methods.dart';
import 'media_store.dart';

/// Removing the attachment blobs of a message that is being deleted.
///
/// Since console 1.9.0 the server frees them itself: a message names its
/// files beside the sealed body (`attachment_paths`, checked to be its
/// sender's own uploads), a delete by anyone puts them in the server's trash,
/// and `sweep_attachments` removes them. That is what a moderator's delete
/// relies on. The database cannot delete an object directly
/// (`storage.protect_delete()`), which is why it goes through the sweep.
///
/// The sender's own delete still removes them here at once, which also
/// covers a message sent before 1.9.0 or to an older server, where nothing
/// names them and the sweep only collects what is older than the oldest
/// message left.
class AttachmentCleanup {
  const AttachmentCleanup._();

  /// Delete the blobs belonging to [message], if it had any.
  ///
  /// Deliberately best-effort and never rethrows. The row is what a person
  /// sees; a blob that outlives it is undecryptable waste that the server-side
  /// sweep collects later. Failing the delete over it — or worse, leaving the
  /// message on screen — would trade something visible for something that
  /// isn't.
  ///
  /// Only for a message of your own. The paths come from the body, and the
  /// body is its sender's to write: a member could name anyone's files in
  /// the conversation, and a manager deleting that message as spam, whom
  /// `chat_attachments_delete` let delete any file in the server before
  /// 1.9.0, would have deleted all of them (review, Nov 22). Only the
  /// uploader may delete a file now; another's are the server's to free.
  /// [origin] is where the files are (`AttachmentLoader.origin`), for
  /// letting go of their bytes here, which happens for any message.
  static Future<void> forMessage(
    ChatMessage? message, {
    required String origin,
    required Future<APIResponse> Function(List<String> paths) delete,
  }) async {
    final attachments = attachmentsOf(message);
    if (attachments.isEmpty) return;

    // Drop the plaintext bytes first. That part can't fail, and it must happen
    // even if the network call does — the message is gone from the UI, so its
    // decrypted images should not survive in memory.
    for (final attachment in attachments) {
      MediaStore.attachments.remove(
        MediaStore.attachmentKey(origin, attachment),
      );
    }
    if (message == null || !message.isMine) return;

    try {
      final response = await delete([
        for (final attachment in attachments) attachment.storagePath,
      ]);
      if (!response.success) {
        HelperMethods.printDebug(
          '[Attachments] blob delete failed, leaving it to the sweep: '
          '${response.error}',
        );
      }
    } catch (e) {
      HelperMethods.printDebug('[Attachments] blob delete threw: $e');
    }
  }

  /// Every file [message] carries: its attachments and a video's poster, a
  /// forward's copies, which its forwarder uploaded as their own, and its
  /// link preview's picture. Empty when it has none.
  static List<Attachment> attachmentsOf(ChatMessage? message) => [
    for (final attachment in [
      ...?message?.attachments,
      ...?message?.forwarded?.attachments,
      ?message?.preview?.image,
    ]) ...[attachment, ?attachment.poster],
  ];

  /// The storage paths of [attachmentsOf].
  static List<String> pathsOf(ChatMessage? message) => [
    for (final attachment in attachmentsOf(message)) attachment.storagePath,
  ];
}
