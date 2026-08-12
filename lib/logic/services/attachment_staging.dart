import 'dart:typed_data';

import '../../data/classes/attachment.dart';
import '../../data/classes/pending_attachment.dart';
import 'byte_format.dart';
import 'image_dimensions.dart';
import 'mime_util.dart';

/// Turning picked bytes into a staged attachment — or into the reason they
/// can't be one.
///
/// Pulled out of the composer because it is the part with rules rather than
/// pixels: which files a server will accept, how many may ride on one message,
/// and what metadata has to be measured *before* upload. Widgets shouldn't
/// hold that (CODE_STYLE §6) and it is worth testing without a running app.
class AttachmentStaging {
  const AttachmentStaging._();

  /// Hard cap on how many files can ride on one message. Bounds quota gaming
  /// — a quota counts messages, not files — and keeps a row readable.
  static const int maxPerMessage = 10;

  /// Why [name] can't be attached, or null if it can.
  ///
  /// The size cap is the server's; the count cap is Rift's. Both are phrased
  /// as complete sentences because they are shown verbatim.
  static String? rejectionFor({
    required String name,
    required int bytes,
    required int maxBytes,
    required int alreadyStaged,
  }) {
    if (alreadyStaged >= maxPerMessage) {
      return 'Up to $maxPerMessage files per message.';
    }
    if (bytes > maxBytes) {
      return '$name is ${humanSize(bytes)} — this server allows up to '
          '${humanSize(maxBytes)} per file.';
    }
    return null;
  }

  /// Build the staged attachment for [bytes].
  ///
  /// Image dimensions are read here rather than on arrival so the receiver's
  /// message list can reserve the right box before it has the bytes to
  /// measure one.
  static Future<PendingAttachment> stage({
    required Uint8List bytes,
    required String name,
    String? mimeType,
  }) async {
    final mime = (mimeType != null && mimeType.isNotEmpty)
        ? mimeType
        : mimeFromName(name);
    final kind = AttachmentKind.fromMime(mime);
    final size = kind == AttachmentKind.image
        ? await readImageDimensions(bytes)
        : null;
    return PendingAttachment(
      bytes: bytes,
      name: name,
      mime: mime,
      kind: kind,
      width: size?.width,
      height: size?.height,
    );
  }
}
