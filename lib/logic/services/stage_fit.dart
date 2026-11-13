import 'dart:math';

/// How big the tiles on a call's stage can be.
///
/// Streams nobody has opened sit in rows of their own above the people, a
/// little larger than a person's tile, and are 16:9. A person's tile is
/// [personAspect] wide for each unit tall. The answer is the largest
/// person-tile width at which both groups, wrapped into rows as wide as
/// [width], still fit in [height].
///
/// People are never one to a row when there are two or more of them: the
/// largest tiles in a tall, narrow window are a single column, and five people
/// stacked like that read as a list, not a call.
///
/// A stream is never narrower than [minStreamWidth] (or the stage) while that
/// still fits: its Watch button, name and quality sit on it, and at a person's
/// width on a phone they ran into each other.
///
/// Searched rather than solved: the height a width costs jumps whenever a row
/// breaks, but it never falls as the width grows, so halving the gap between
/// a width that fits and one that does not converges on the best one.
({double tileWidth, double streamWidth}) stageFit({
  required double width,
  required double height,
  required int people,
  required int streams,
  double gap = 8,
  double streamScale = 1.25,
  double minStreamWidth = 0,
  double personAspect = 16 / 9,
}) {
  double streamWidthFor(double tile) =>
      min(max(tile * streamScale, minStreamWidth), width);

  double heightFor(double tile) {
    double groupHeight(int count, double tileWidth, double aspect) {
      if (count == 0) return 0;
      final perRow = max(1, ((width + gap) / (tileWidth + gap)).floor());
      final rows = (count / perRow).ceil();
      return rows * tileWidth / aspect + (rows - 1) * gap;
    }

    final between = people > 0 && streams > 0 ? gap : 0;
    return groupHeight(streams, streamWidthFor(tile), 16 / 9) +
        between +
        groupHeight(people, tile, personAspect);
  }

  // A stage too short for the streams at their least: they shrink with the
  // people, as before there was a least.
  if (minStreamWidth > 0 && streams > 0 && heightFor(0) > height) {
    return stageFit(
      width: width,
      height: height,
      people: people,
      streams: streams,
      gap: gap,
      streamScale: streamScale,
      personAspect: personAspect,
    );
  }

  var low = 0.0;
  var high = people >= 2 ? (width - gap) / 2 : width;
  if (heightFor(high) <= height) low = high;
  for (var i = 0; i < 30 && high - low > 0.5; i++) {
    final mid = (low + high) / 2;
    if (heightFor(mid) <= height) {
      low = mid;
    } else {
      high = mid;
    }
  }
  final tile = low.floorToDouble();
  return (tileWidth: tile, streamWidth: streamWidthFor(tile).floorToDouble());
}
