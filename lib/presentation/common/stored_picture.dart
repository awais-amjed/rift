import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/media/media_cubit.dart';
import 'squircle_avatar.dart';

/// A square picture from [MediaCubit], or the initial on a gradient until it
/// is there — what [UserAvatar] and [DirectoryIcon] both draw.
///
/// Selects its own entry, so a picture landing rebuilds only the widgets
/// showing it, and every one of them at once. Asking for the picture is the
/// caller's job: this only draws what is held.
class StoredPicture extends StatelessWidget {
  final String? path;

  /// Supplies the initial for the fallback.
  final String name;
  final double size;

  /// Stable id picking the fallback gradient.
  final String? seed;

  const StoredPicture({
    super.key,
    required this.path,
    required this.name,
    required this.size,
    this.seed,
  });

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    if (path == null) return _fallback();
    return BlocSelector<MediaCubit, MediaState, Uint8List?>(
      selector: (state) => state.bytes(MediaKind.image, path),
      builder: (context, bytes) {
        // No picture yet → the same squircle-and-gradient everything else
        // uses, so a member with an avatar and one without still look like
        // two members rather than two different kinds of thing.
        if (bytes == null) return _fallback();
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * K.avatarRadiusRatio),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }

  Widget _fallback() => SquircleAvatar(name: name, seed: seed, size: size);
}
