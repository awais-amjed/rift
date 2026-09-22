import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import '../helper_methods.dart';

/// Reads an encoded image's pixel dimensions without decoding it.
///
/// Recorded on the attachment when a picture is picked so the message list can
/// reserve the right box before the bytes arrive. [ui.ImageDescriptor] parses
/// only the header, so this costs nothing next to a full decode — and the
/// alternative, letting the row resize when the image lands, drags everything
/// below it down the moment a decrypt finishes.
Future<({int width, int height})?> readImageDimensions(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (width: descriptor.width, height: descriptor.height);
  } catch (e) {
    // A format this platform can't parse is not worth failing a send over —
    // the thumbnail just falls back to sizing itself once decoded.
    HelperMethods.printDebug('readImageDimensions: could not read header – $e');
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
