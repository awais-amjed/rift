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

/// Open the file picker and return a picture ready to upload.
///
/// Every step a caller would otherwise repeat: the type filter, the MIME
/// check that catches a `.png` which is not one, the size refusal before any
/// decode is attempted, and the downscale — so what gets uploaded is what
/// everybody else has to download (see [AvatarImage]).
///
/// It lives here because there are two of these now, a profile avatar and a
/// bot listing's icon, and they want the identical picture: a small square
/// drawn at 40 logical pixels. A second copy of this would be a second place
/// for the size ceiling to drift away from the bucket's.
Future<PickedPicture> pickPicture({String context = 'Picture'}) async {
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

    final prepared = await AvatarImage.prepare(source);
    if (prepared == null) {
      return (bytes: null, error: "Couldn't read that image.");
    }
    return (bytes: prepared, error: null);
  } catch (e) {
    HelperMethods.printDebug('[$context] picture pick failed: $e');
    return (bytes: null, error: "Couldn't open that file.");
  }
}
