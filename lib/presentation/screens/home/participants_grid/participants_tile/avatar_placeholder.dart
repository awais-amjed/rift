import 'package:flutter/material.dart';

import '../../../../common/member_avatar.dart';

/// Stands in for a participant who has no camera on.
///
/// Their picture, or the same squircle and identity gradient as everywhere
/// else, just large: a tile with the camera off should still show *who* it is.
class AvatarPlaceholder extends StatelessWidget {
  final String name;

  /// The participant's *user* id, which picks their picture and their
  /// colour. A LiveKit identity is the wrong thing to pass: it varies by
  /// device and by screenshare, and neither would be found under it.
  final String userId;

  const AvatarPlaceholder({
    super.key,
    required this.name,
    required this.userId,
  });

  static const _maxSize = 96.0;

  @override
  Widget build(BuildContext context) {
    // Centred, with the name badge free to sit over it — its own background
    // keeps it readable. Sized to the tile, though: the row under a screen
    // share is under 100px tall, and a fixed 96 was cut off top and bottom.
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: MemberAvatar(
          userId: userId,
          name: name,
          size: (constraints.biggest.shortestSide * 0.7).clamp(0.0, _maxSize),
        ),
      ),
    );
  }
}
