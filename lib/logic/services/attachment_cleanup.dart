import '../../data/classes/api_response.dart';
import '../../data/classes/attachment.dart';
import '../../data/classes/chat_message.dart';
import '../helper_methods.dart';
import 'media_store.dart';

/// Removing the attachment blobs of a message that is being deleted.
///
/// This has to happen on the client, and it is worth saying why, because the
/// tidier-looking answers don't work:
///
///   * The **server can't find them.** An attachment's storage path lives
///     inside the E2E-encrypted message body — that is the whole design. Only
///     a client that has decrypted the message knows which blobs are its own.
///   * The **database can't delete them.** `storage.protect_delete()` refuses a
///     direct DELETE on `storage.objects` ("Use the Storage API instead"), so
///     an `ON DELETE CASCADE` from a message→blob table would have freed zero
///     bytes. Such a table would have bought a metadata leak and nothing else.
///
/// So the client does the precise deletion, and `sweep_attachments` on the
/// server cleans up whatever no client ever got to.
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
  /// `chat_attachments_delete` lets delete any file in the server, would
  /// have deleted all of them (review, Nov 22). Another's are left to the
  /// sweep. [origin] is where the files are (`AttachmentLoader.origin`), for
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
