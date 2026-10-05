import 'dart:math';

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

  /// How much of the tile's foot the name badge covers, which the avatar
  /// keeps out of.
  final double clearBottom;

  const AvatarPlaceholder({
    super.key,
    required this.name,
    required this.userId,
    this.clearBottom = 0,
  });

  static const _maxSize = 96.0;

  /// The share of the room above the badge an avatar moved up into takes,
  /// leaving the rest as space around it.
  static const _fillAbove = 0.85;

  @override
  Widget build(BuildContext context) {
    // Sized to the tile: the row under a screen share is under 100px tall,
    // and a fixed 96 was cut off top and bottom. Centred where that clears
    // the name badge; in a tile too short for that, it moves up into the room
    // above the badge, smaller. Centred regardless, the badge covered a third
    // of it in that row, and half on a phone (Oct 5 2026).
    return LayoutBuilder(
      builder: (context, constraints) {
        final tile = constraints.biggest;
        final above = tile.height - clearBottom;
        final size = (tile.shortestSide * 0.7).clamp(0.0, _maxSize);
        Widget avatar(double size) =>
            MemberAvatar(userId: userId, name: name, size: size);
        if ((tile.height + size) / 2 <= above) {
          return Center(child: avatar(size));
        }
        final fitted = max(0.0, min(size, above * _fillAbove));
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: max(0.0, (above - fitted) / 2)),
            child: avatar(fitted),
          ),
        );
      },
    );
  }
}
