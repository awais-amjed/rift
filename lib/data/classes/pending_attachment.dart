import 'dart:typed_data';

import 'attachment.dart';

/// A file the user has staged in the composer but not yet sent: raw bytes plus
/// display metadata. On send it's encrypted, uploaded, and turned into an
/// [Attachment] (which carries the storage path + per-file key instead of bytes).
/// Immutable: [plain] changes by [copyWith], so the composer replaces the
/// staged entry.
class PendingAttachment {
  final Uint8List bytes;
  final String name;
  final String mime;
  final AttachmentKind kind;
  final int? width;
  final int? height;
  final int? durationMs;

  /// The sender chose to upload this one unencrypted. Offered only for big
  /// files (`K.plainAttachmentMinBytes`) on a self-hosted server.
  final bool plain;

  const PendingAttachment({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.kind,
    this.width,
    this.height,
    this.durationMs,
    this.plain = false,
  });

  int get size => bytes.length;

  PendingAttachment copyWith({bool? plain}) => PendingAttachment(
    bytes: bytes,
    name: name,
    mime: mime,
    kind: kind,
    width: width,
    height: height,
    durationMs: durationMs,
    plain: plain ?? this.plain,
  );
}
