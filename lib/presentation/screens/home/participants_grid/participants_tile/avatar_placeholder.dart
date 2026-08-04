import 'package:flutter/material.dart';

import '../../../../common/squircle_avatar.dart';

/// Stands in for a participant who has no camera on.
///
/// The same squircle and identity gradient as everywhere else, just large:
/// a tile with the camera off should still show *who* it is, and the
/// gradient does that faster than an initial on grey.
class AvatarPlaceholder extends StatelessWidget {
  final String name;

  /// The participant's identity, so their colour matches their avatar
  /// everywhere else in the app.
  final String? seed;

  const AvatarPlaceholder({super.key, required this.name, this.seed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SquircleAvatar(name: name, seed: seed, size: 112),
    );
  }
}
