import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../helper_methods.dart';
import 'avatar_image.dart';
import 'mime_util.dart';

/// What [pickPicture] answers: the prepared bytes, or the sentence to show.
///
/// Never both, and never neither unless the person cancelled — in which case
/// both are null and the caller should leave what it had on screen alone.
typedef PickedPicture = ({Uint8List? bytes, String? error});

/// Open the file picker, let the person crop what they picked, and return a
/// picture ready to upload.
///
/// Every step a caller would otherwise repeat: the type filter, the MIME
/// check that catches a `.png` which is not one, the size refusal before any
/// decode is attempted, and the downscale — so what gets uploaded is what
/// everybody else has to download (see [AvatarImage]).
///
/// It lives here because there are three of these, a profile avatar, a
/// server icon and a bot listing's icon, and they want the identical
/// picture: a small square drawn at 40 logical pixels. A second copy of this
/// would be a second place for the size ceiling to drift away from the
/// bucket's.
///
/// [crop] is the crop dialog, handed in from the screen, since a service
/// draws nothing. It is given the picture already shrunk to
/// [AvatarImage.cropSourceDimension] and answers the square cut from it, or
/// null when the person backed out, which reads as a cancel.
Future<PickedPicture> pickPicture({
  required Future<Uint8List?> Function(Uint8List picture) crop,
  String context = 'Picture',
}) async {
  try {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
        ),
      ],
    );
    // Cancelled. Not an error, and not a change either.
    if (file == null) return (bytes: null, error: null);

    final mime = (file.mimeType?.isNotEmpty ?? false)
        ? file.mimeType!
        : mimeFromName(file.name);
    if (!AvatarImage.isSupportedMime(mime)) {
      return (bytes: null, error: "That file isn't an image we can use.");
    }

    final source = await file.readAsBytes();
    if (!AvatarImage.isAcceptableSize(source.length)) {
      return (bytes: null, error: 'That image is too large.');
    }

    final toCrop = await AvatarImage.prepare(
      source,
      max: AvatarImage.cropSourceDimension,
    );
    if (toCrop == null) {
      return (bytes: null, error: "Couldn't read that image.");
    }
    final cropped = await crop(toCrop);
    if (cropped == null) return (bytes: null, error: null);

    final prepared = await AvatarImage.prepare(cropped);
    if (prepared == null) {
      return (bytes: null, error: "Couldn't read that image.");
    }
    return (bytes: prepared, error: null);
  } catch (e) {
    HelperMethods.printDebug('[$context] picture pick failed: $e');
    return (bytes: null, error: "Couldn't open that file.");
  }
}
