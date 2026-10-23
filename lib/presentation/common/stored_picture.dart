import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/media/media_cubit.dart';
import '../../logic/services/media_store.dart';
import 'rounded_picture.dart';
import 'squircle_avatar.dart';

/// A square picture from [MediaCubit], or the initial on a gradient until it
/// is there — what [UserAvatar], [DirectoryIcon] and [ServerIcon] draw.
///
/// Selects its own entry, so a picture landing rebuilds only the widgets
/// showing it, and every one of them at once. Asking for the picture is the
/// caller's job: this only draws what is held.
class StoredPicture extends StatelessWidget {
  /// The host [path] is on, the one its fetch named. A picture is held under
  /// both (`MediaStore.keyOf`), so a server repeating another's path draws
  /// only its own bytes. Without one, nothing is drawn but the initial.
  final String? origin;
  final String? path;

  /// Supplies the initial for the fallback.
  final String name;
  final double size;

  /// Stable id picking the fallback gradient.
  final String? seed;

  /// Corner radius; defaults to the avatar's, size/3.
  final double? radius;

  const StoredPicture({
    super.key,
    required this.origin,
    required this.path,
    required this.name,
    required this.size,
    this.seed,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final origin = this.origin;
    final path = this.path;
    if (origin == null || path == null) return _fallback();
    final key = MediaStore.keyOf(origin, path);
    return BlocSelector<MediaCubit, MediaState, Uint8List?>(
      selector: (state) => state.bytes(MediaKind.image, key),
      builder: (context, bytes) {
        // No picture yet → the same squircle-and-gradient everything else
        // uses, so a member with an avatar and one without still look like
        // two members rather than two different kinds of thing.
        if (bytes == null) return _fallback();
        return RoundedPicture(
          image: MemoryImage(bytes),
          size: size,
          radius: radius ?? size * K.avatarRadiusRatio,
        );
      },
    );
  }

  Widget _fallback() =>
      SquircleAvatar(name: name, seed: seed, size: size, radius: radius);
}
