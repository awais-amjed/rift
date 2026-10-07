import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'attachment.dart';

/// A file the user has staged in the composer but not yet sent, plus display
/// metadata. On send it's encrypted, uploaded, and turned into an
/// [Attachment] (which carries the storage path + per-file key instead of
/// bytes). Immutable: [plain] changes by [copyWith], so the composer replaces
/// the staged entry.
///
/// **Two kinds, by size.** A small file — every picture, every voice note —
/// is read into [bytes] when it is staged, because the chip has to show it
/// and the sender's own copy is drawn from memory. A big one is held only as
/// [file] and read a chunk at a time as it is sent, so a file larger than the
/// device's memory can go: see `AttachmentStaging.inMemoryMaxBytes`.
class PendingAttachment {
  /// The whole file, for one small enough to hold. Null for a big one.
  final Uint8List? bytes;

  /// Where a big file is read from. Null for one held in [bytes].
  final XFile? file;

  /// Bytes in the file, known without reading it.
  final int size;

  final String name;
  final String mime;
  final AttachmentKind kind;
  final int? width;
  final int? height;
  final int? durationMs;

  /// The sender chose to upload this one unencrypted. Offered only for big
  /// files (`K.plainAttachmentMinBytes`) on a self-hosted server.
  final bool plain;

  PendingAttachment({
    required Uint8List this.bytes,
    required this.name,
    required this.mime,
    required this.kind,
    this.width,
    this.height,
    this.durationMs,
    this.plain = false,
  }) : file = null,
       size = bytes.length;

  /// A big file, read when it is sent.
  const PendingAttachment.file({
    required XFile this.file,
    required this.size,
    required this.name,
    required this.mime,
    required this.kind,
    this.width,
    this.height,
    this.durationMs,
    this.plain = false,
  }) : bytes = null;

  const PendingAttachment._({
    required this.bytes,
    required this.file,
    required this.size,
    required this.name,
    required this.mime,
    required this.kind,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.plain,
  });

  /// Whether it is read from [file] as it goes rather than held.
  bool get streams => bytes == null;

  /// The file to read from, either way: [file], or [bytes] wrapped as one.
  XFile get source => file ?? XFile.fromData(bytes!, name: name, length: size);

  PendingAttachment copyWith({bool? plain}) => PendingAttachment._(
    bytes: bytes,
    file: file,
    size: size,
    name: name,
    mime: mime,
    kind: kind,
    width: width,
    height: height,
    durationMs: durationMs,
    plain: plain ?? this.plain,
  );
}
