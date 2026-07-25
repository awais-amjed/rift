import 'dart:typed_data';

import 'attachment.dart';

/// A file the user has staged in the composer but not yet sent: raw bytes plus
/// display metadata. On send it's encrypted, uploaded, and turned into an
/// [Attachment] (which carries the storage path + per-file key instead of bytes).
class PendingAttachment {
  final Uint8List bytes;
  final String name;
  final String mime;
  final AttachmentKind kind;
  final int? width;
  final int? height;
  final int? durationMs;

  const PendingAttachment({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.kind,
    this.width,
    this.height,
    this.durationMs,
  });

  int get size => bytes.length;
}
