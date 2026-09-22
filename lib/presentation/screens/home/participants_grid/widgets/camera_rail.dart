import 'package:flutter/material.dart';

/// The row of people under a screen share.
///
/// Tiles shrink to fit the width before anything scrolls: a scrolling row
/// showed two people and a sliver of the third, with nothing saying there was
/// more. Only when they would be too small to recognise does it scroll.
///
/// Fitted tiles are drawn unclipped. A speaking tile's ring and glow are
/// outside its box, and a list clips to its own bounds, so the ring was cut to
/// two stray bars at the tile's sides.
class CameraRail extends StatelessWidget {
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double gap;

  const CameraRail({
    super.key,
    required this.count,
    required this.itemBuilder,
    required this.height,
    required this.gap,
  });

  static const _aspect = 16 / 9;

  /// Narrower than this and a name badge no longer fits beside anything.
  static const _minTileWidth = 112.0;

  /// Room for the speaking ring's hard edge when the row does scroll and has
  /// to clip; the soft glow past it is lost there.
  static const _ringRoom = 4.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = (constraints.maxWidth - gap * (count - 1)) / count;
          final width = fitted.clamp(0.0, height * _aspect);
          if (width >= _minTileWidth) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: gap,
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(
                    width: width,
                    height: width / _aspect,
                    child: itemBuilder(context, i),
                  ),
              ],
            );
          }
          final tileHeight = height - _ringRoom * 2;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(_ringRoom),
            itemCount: count,
            separatorBuilder: (_, _) => SizedBox(width: gap),
            itemBuilder: (context, index) => SizedBox(
              width: tileHeight * _aspect,
              child: itemBuilder(context, index),
            ),
          );
        },
      ),
    );
  }
}
