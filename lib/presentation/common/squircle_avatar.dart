import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/identity_gradients.dart';

/// The app's one avatar: a squircle showing an image, or the identity's
/// initial on its own gradient.
///
/// Squircles rather than circles, at radius ≈ size/3, so avatars sit in the
/// same shape family as the server chips and panels around them.
class SquircleAvatar extends StatelessWidget {
  /// Supplies the initial when there's no image.
  final String name;

  /// The letter this avatar draws: the first letter or digit in [name], not
  /// simply its first character.
  ///
  /// A handle is shown with its `@` — the DM header's title is
  /// `@lana_clean` — and taking character zero drew an avatar with `@` on it
  /// while the conversation list beside it, given the bare handle, drew `L`
  /// for the same person. Punctuation is never the initial anyone means.
  static String initialOf(String name) {
    for (final rune in name.runes) {
      final character = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z0-9]').hasMatch(character)) {
        return character.toUpperCase();
      }
    }
    // Nothing alphanumeric at all: a name that is only emoji or CJK keeps its
    // first character, because that *is* what somebody would call it.
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }

  /// Stable id that picks the gradient. Falls back to [name], which is fine
  /// for servers but wrong for people — pass a user id so a rename doesn't
  /// change someone's colour.
  final String? seed;

  final String? imageUrl;
  final double size;

  /// Corner radius. Defaults to size/3; the voice stage's large placeholder
  /// takes a softer corner, since size/3 on a 96px square reads as a circle.
  final double? radius;

  const SquircleAvatar({
    super.key,
    required this.name,
    this.seed,
    this.imageUrl,
    this.size = 40,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      this.radius ?? size * K.avatarRadiusRatio,
    );

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _buildInitial(radius),
        ),
      );
    }
    return _buildInitial(radius);
  }

  Widget _buildInitial(BorderRadius radius) {
    final identity = IdentityGradients.forSeed(seed ?? name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: identity.gradient,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Text(
        initialOf(name),
        style: TextStyle(
          color: identity.onColor,
          fontWeight: FontWeight.w700,
          // Tracks the box so one avatar widget covers 22px sidebar rows and
          // 40px rail chips without a second size scale.
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}
