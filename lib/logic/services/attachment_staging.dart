import 'package:cross_file/cross_file.dart';

import '../../data/classes/attachment.dart';
import '../../data/classes/pending_attachment.dart';
import 'byte_format.dart';
import 'file_save/save_target.dart';
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

  /// The largest file read into memory when it is staged. Anything bigger
  /// stays where it is and is read a chunk at a time as it is sent — and is
  /// sealed a chunk at a time, which an older client cannot open — so this is
  /// also where chunking starts. Above central's 10 MB, so a central DM never
  /// sends a chunked file; well above any picture or voice note.
  static const int inMemoryMaxBytes = 16 * 1024 * 1024;

  /// Why [name] can't be attached, or null if it can.
  ///
  /// The size cap is the server's; the count cap is Rift's. Both are phrased
  /// as complete sentences because they are shown verbatim.
  /// [remainingBytes] is what the server has room for, or
  /// null when it has no storage limit. [stagedBytes] is what this message is
  /// already carrying, which counts against it — five files that each fit and
  /// together do not is the case a per-file check alone would wave through.
  static String? rejectionFor({
    required String name,
    required int bytes,
    required int maxBytes,
    required int alreadyStaged,
    int? remainingBytes,
    int stagedBytes = 0,
  }) {
    if (alreadyStaged >= maxPerMessage) {
      return 'Up to $maxPerMessage files per message.';
    }
    if (bytes > maxBytes) {
      return '$name is ${humanSize(bytes)} — this server allows up to '
          '${humanSize(maxBytes)} per file.';
    }
    // Last, because it is the one that is not the file's fault. A file that
    // is simply too big should be told so whether or not the server is also
    // full.
    if (remainingBytes != null && stagedBytes + bytes > remainingBytes) {
      final left = remainingBytes - stagedBytes;
      return left <= 0
          ? 'This server is out of attachment space — an admin can free '
                'some up or raise the limit.'
          : '$name is ${humanSize(bytes)} and this server has only '
                '${humanSize(left)} of attachment space left.';
    }
    return null;
  }

  /// Build the staged attachment for [file], [size] bytes.
  ///
  /// A file up to [inMemoryMaxBytes] is read now; a bigger one is only
  /// pointed at. Image dimensions are read here rather than on arrival so the
  /// receiver's message list can reserve the right box before it has the
  /// bytes to measure one — for a picture held in memory, which is every
  /// picture anybody sends.
  ///
  /// [temporary] says [file] is a copy made to be sent
  /// ([PendingAttachment.temporary]). One read into memory here is deleted
  /// at once; a big one goes when the send is over.
  static Future<PendingAttachment> stage({
    required XFile file,
    required int size,
    required String name,
    String? mimeType,
    bool temporary = false,
  }) async {
    final mime = (mimeType != null && mimeType.isNotEmpty)
        ? mimeType
        : mimeFromName(name);
    final kind = AttachmentKind.fromMime(mime);
    if (size > inMemoryMaxBytes) {
      return PendingAttachment.file(
        file: file,
        size: size,
        name: name,
        mime: mime,
        kind: kind,
        temporary: temporary,
      );
    }
    final bytes = await file.readAsBytes();
    if (temporary) await discardCopy(file);
    final dimensions = kind == AttachmentKind.image
        ? await readImageDimensions(bytes)
        : null;
    return PendingAttachment(
      bytes: bytes,
      name: name,
      mime: mime,
      kind: kind,
      width: dimensions?.width,
      height: dimensions?.height,
    );
  }

  /// Delete the copies among [files] ([PendingAttachment.temporary]), once
  /// nothing will read them again: the send is over, or the file was taken
  /// out of the composer.
  static Future<void> discard(Iterable<PendingAttachment> files) async {
    for (final staged in files) {
      if (staged.file case final copy? when staged.temporary) {
        await discardCopy(copy);
      }
    }
  }
}
