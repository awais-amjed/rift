import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:equatable/equatable.dart';

import 'attachment.dart';
import 'equality_props.dart';

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
class PendingAttachment extends Equatable {
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

  /// [file] is a copy made for this message — a phone's picker hands one
  /// over, and a file dropped into the sandboxed macOS app is read out into
  /// one — so it is deleted once nothing will read it again
  /// (`AttachmentStaging.discard`). Never set on a file the person owns.
  final bool temporary;

  // Not const: [size] is read off the bytes.
  // ignore: prefer_const_constructors_in_immutables
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
       size = bytes.length,
       temporary = false;

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
    this.temporary = false,
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
    required this.temporary,
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
    temporary: temporary,
  );

  @override
  List<Object?> get props => [
    IdentityProp(bytes),
    file,
    size,
    name,
    mime,
    kind,
    width,
    height,
    durationMs,
    plain,
    temporary,
  ];
}
