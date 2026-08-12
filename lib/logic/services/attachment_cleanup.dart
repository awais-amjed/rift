import '../../data/classes/api_response.dart';
import '../../data/classes/chat_message.dart';
import '../helper_methods.dart';
import 'attachment_cache.dart';

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
  static Future<void> forMessage(
    ChatMessage? message, {
    required Future<APIResponse> Function(List<String> paths) delete,
  }) async {
    final paths = pathsOf(message);
    if (paths.isEmpty) return;

    // Drop the plaintext bytes first. That part can't fail, and it must happen
    // even if the network call does — the message is gone from the UI, so its
    // decrypted images should not survive in memory.
    for (final path in paths) {
      AttachmentCache.instance.remove(path);
    }

    try {
      final response = await delete(paths);
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

  /// The storage paths [message] carries, or empty when it has none.
  static List<String> pathsOf(ChatMessage? message) => [
    for (final attachment in message?.attachments ?? const [])
      attachment.storagePath,
  ];
}
