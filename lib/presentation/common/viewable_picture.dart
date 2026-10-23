import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/media/media_cubit.dart';
import '../../logic/services/media_store.dart';
import 'image_viewer.dart';

/// A profile's picture that opens full size when clicked: the whole square,
/// without the rounded corners every avatar and icon cuts off it.
///
/// Clickable only while [MediaCubit] holds the picture. With none, or until
/// it lands, the initial is drawn instead, and there is nothing to open.
class ViewablePicture extends StatelessWidget {
  /// The host and path [child] draws from (`StoredPicture`), so this opens
  /// exactly the bytes on screen.
  final String? origin;
  final String? path;

  /// Names the file when the picture is saved from the viewer.
  final String name;

  final Widget child;

  /// How large the viewer draws the picture, past its own pixels.
  static const double viewWidth = 420;

  const ViewablePicture({
    super.key,
    required this.origin,
    required this.path,
    required this.name,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final origin = this.origin;
    final path = this.path;
    if (origin == null || path == null) return child;
    final key = MediaStore.keyOf(origin, path);
    return BlocSelector<MediaCubit, MediaState, Uint8List?>(
      selector: (state) => state.bytes(MediaKind.image, key),
      builder: (context, bytes) {
        if (bytes == null) return child;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            // The whole square, not only its painted pixels: a picture with
            // a clear background is still one picture.
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                showImageViewer(context, '$name.png', bytes, width: viewWidth),
            child: child,
          ),
        );
      },
    );
  }
}
