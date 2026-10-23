import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../../logic/helper_methods.dart';
import '../../theme/app_text.dart';
import '../../theme/media_colors.dart';
import '../../theme/theme_context.dart';
import '../app_button.dart';
import '../app_modal.dart';
import '../loading_block.dart';

/// Choose the square of a picture that becomes an avatar or icon: drag the
/// picture under a fixed frame, and scroll or pinch to zoom.
///
/// The frame is drawn with the corners the picture will have everywhere it
/// is shown, so what is inside it is what everybody else sees. It stays put
/// and the picture moves, rather than a frame dragged by its corners, since
/// the shape is fixed and only what fills it is a choice.
///
/// Pops with the cut square as encoded bytes, or null when the person backs
/// out. The cutting is `crop_your_image`'s, off the main isolate.
class PictureCropDialog extends StatefulWidget {
  /// Already shrunk to `AvatarImage.cropSourceDimension`, which is what
  /// keeps the decode and the cut quick.
  final Uint8List picture;

  const PictureCropDialog({super.key, required this.picture});

  @override
  State<PictureCropDialog> createState() => _PictureCropDialogState();
}

class _PictureCropDialogState extends State<PictureCropDialog> {
  final _controller = CropController();
  CropStatus _status = CropStatus.nothing;
  String? _error;

  /// The largest the crop area is drawn.
  static const double _viewport = 320;

  /// How much of the area the frame takes, leaving a margin of the picture
  /// round it so it reads as a frame over something larger.
  static const double _frameShare = 0.84;

  static const double _width = 400;

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure(:final cause):
        HelperMethods.printDebug('[Crop] cutting the picture failed: $cause');
        setState(() {
          _status = CropStatus.ready;
          _error = "Couldn't crop that picture.";
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final busy = _status != CropStatus.ready;
    return AppModal(
      title: 'Crop picture',
      maxWidth: _width,
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.maxWidth < _viewport
                  ? constraints.maxWidth
                  : _viewport;
              final frame = side * _frameShare;
              return ClipRRect(
                borderRadius: BorderRadius.circular(K.radiusCard),
                child: SizedBox.square(
                  dimension: side,
                  child: Crop(
                    image: widget.picture,
                    controller: _controller,
                    onCropped: _onCropped,
                    onStatusChanged: (status) =>
                        setState(() => _status = status),
                    aspectRatio: 1,
                    interactive: true,
                    fixCropRect: true,
                    initialRectBuilder: InitialRectBuilder.withBuilder(
                      (viewport, _) => Rect.fromCenter(
                        center: viewport.center,
                        width: frame,
                        height: frame,
                      ),
                    ),
                    radius: frame * K.avatarRadiusRatio,
                    // No handles: the frame is not dragged by its corners.
                    cornerDotBuilder: (_, _) => const SizedBox.shrink(),
                    baseColor: theme.bgTertiary,
                    maskColor: MediaColors.scrim,
                    progressIndicator: const LoadingBlock(),
                  ),
                ),
              );
            },
          ),
          Text(
            'Drag to move the picture. Scroll or pinch to zoom.',
            textAlign: TextAlign.center,
            style: AppText.secondary.copyWith(color: theme.textTertiary),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Apply',
          isLoading: _status == CropStatus.cropping,
          onPressed: busy ? null : _controller.crop,
        ),
      ],
    );
  }
}
