import 'dart:typed_data';

import '../../../../data/classes/attachment.dart';

/// Fetches + decrypts an attachment's bytes on demand (from the in-memory
/// cache or a network download). Returns null on failure. Each chat view wires
/// this to its cubit's `loadAttachment`.
typedef AttachmentLoader = Future<Uint8List?> Function(Attachment attachment);
