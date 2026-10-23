import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../logic/services/pick_picture.dart';
import '../show_custom_dialog.dart';
import 'picture_crop_dialog.dart';

/// Pick a picture and crop it to the square it will be shown in: what the
/// Edit profile, server icon and bot icon pickers all do.
///
/// [purpose] names the picker in the log.
Future<PickedPicture> choosePicture(
  BuildContext context, {
  required String purpose,
}) {
  return pickPicture(
    context: purpose,
    // After the file picker, which the screen may not have outlived.
    crop: (picture) async => context.mounted
        ? showCustomDialog<Uint8List>(
            context: context,
            build: (_) => PictureCropDialog(picture: picture),
          )
        : null,
  );
}
