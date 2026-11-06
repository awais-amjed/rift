import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../logic/services/screen_share_sources.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import 'source_tile.dart';

/// The windows or screens to pick from, as tiles: with their pictures on
/// Windows, the only capturer that makes them, and elsewhere with an icon and
/// the window's app where it is known (X11), so every platform's list looks
/// alike.
///
/// It has a page of the dialog to itself, so a tile is big enough to recognise
/// a window by: three to a row in a big window, two in a smaller one, and one
/// in the narrowest. More than fit scroll.
class SourceThumbnailGrid extends StatelessWidget {
  final List<CaptureSource> sources;
  final int? selectedIndex;
  final Map<int, Uint8List> thumbnails;
  final bool captureFullScreen;
  final ValueChanged<CaptureSource> onChanged;

  const SourceThumbnailGrid({
    super.key,
    required this.sources,
    required this.selectedIndex,
    required this.thumbnails,
    required this.captureFullScreen,
    required this.onChanged,
  });

  static const _gap = 12.0;

  /// Keeps the tiles clear of the scrollbar.
  static const _scrollbarRoom = 8.0;

  static int _columnsFor(double width) => width >= 840
      ? 3
      : width >= 420
      ? 2
      : 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - _scrollbarRoom;
        final columns = _columnsFor(room);
        final tile = (room - _gap * (columns - 1)) / columns;
        return GridView.builder(
          padding: const EdgeInsets.only(right: _scrollbarRoom),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: _gap,
            mainAxisSpacing: _gap,
            mainAxisExtent: tile * 9 / 16 + SourceTile.labelHeight,
          ),
          itemCount: sources.length,
          itemBuilder: (context, i) {
            final source = sources[i];
            return SourceTile(
              label: ScreenShareSources.labelOf(source, captureFullScreen),
              thumbnail: thumbnails[source.index],
              screen: captureFullScreen,
              app: source.appId,
              minimised: source.minimised,
              selected: source.index == selectedIndex,
              onTap: () => onChanged(source),
            );
          },
        );
      },
    );
  }
}
