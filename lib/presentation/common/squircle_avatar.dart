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

  /// Stable id that picks the gradient. Falls back to [name], which is fine
  /// for servers but wrong for people — pass a user id so a rename doesn't
  /// change someone's colour.
  final String? seed;

  final String? imageUrl;
  final double size;

  const SquircleAvatar({
    super.key,
    required this.name,
    this.seed,
    this.imageUrl,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * K.avatarRadiusRatio);

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
        name.isNotEmpty ? name[0].toUpperCase() : '?',
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
