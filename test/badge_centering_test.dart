import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/presentation/common/unread_badge.dart';
import 'package:rift/presentation/responsive/phone_text_scale.dart';
import 'package:rift/presentation/screens/home/servers/server_rail/widgets/rail_unread_badge.dart';
import 'package:rift/presentation/theme/app_palette.dart';
import 'package:rift/presentation/theme/app_theme.dart';

import 'helpers/memory_storage.dart';

/// The count sits in the middle of its pill. At the old line height every
/// count drew a pixel low, and the rail's a pixel high — which nobody saw by
/// reading the widgets, since it depends on the font's metrics and on glyphs
/// landing on whole pixels. So these render Geist itself and measure the ink.
void main() {
  setUpAll(() async {
    HydratedBloc.storage = MemoryStorage();
    final loader = FontLoader('Geist');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/Geist-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  const ratio = 8.0;

  /// The spare pixels above and below the count, inside the pill's fill.
  Future<(double, double)> margins(
    WidgetTester tester,
    Widget badge,
    double scale,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromPalette(AppPalette.all.first, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Material(
            // On a whole pixel, so the image holds the badge as it paints.
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(child: badge),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).last,
    );
    late Uint8List px;
    late int w, h;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: ratio);
      w = image.width;
      h = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      px = data!.buffer.asUint8List();
      image.dispose();
    });
    int at(int x, int y) => (y * w + x) * 4;

    // Only the columns the count is drawn in: the pill's curved ends and the
    // rail badge's ring stay out of the reading.
    final pill = tester.getRect(find.byType(RepaintBoundary).last);
    final text = tester.getRect(find.byType(RichText).last);
    final from = ((text.left - pill.left) * ratio).round();
    final to = ((text.right - pill.left) * ratio).round();

    // The fill is the commonest colour there.
    final tally = <int, int>{};
    for (var y = 0; y < h; y++) {
      for (var x = from; x < to; x++) {
        final i = at(x, y);
        if (px[i + 3] < 250) continue;
        final rgb = px[i] << 16 | px[i + 1] << 8 | px[i + 2];
        tally[rgb] = (tally[rgb] ?? 0) + 1;
      }
    }
    final fill = tally.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    int distance(int i) =>
        (px[i] - (fill >> 16)).abs() +
        (px[i + 1] - (fill >> 8 & 0xFF)).abs() +
        (px[i + 2] - (fill & 0xFF)).abs();

    bool isFill(int x, int y) =>
        px[at(x, y) + 3] == 255 && distance(at(x, y)) < 30;

    // Ink is what lies between a column's first and last fill pixel, so the
    // transparent corners and the ring above and below the fill never count.
    var top = h, bottom = -1, inkTop = h, inkBottom = -1;
    for (var x = from; x < to; x++) {
      var first = 0;
      while (first < h && !isFill(x, first)) {
        first++;
      }
      var last = h - 1;
      while (last > first && !isFill(x, last)) {
        last--;
      }
      if (first < top) top = first;
      if (last > bottom) bottom = last;
      for (var y = first + 1; y < last; y++) {
        if (distance(at(x, y)) > 120) {
          if (y < inkTop) inkTop = y;
          if (y > inkBottom) inkBottom = y;
        }
      }
    }
    return ((inkTop - top) / ratio, (bottom - inkBottom) / ratio);
  }

  for (final scale in [1.0, PhoneTextScale.factor]) {
    for (final count in [1, 2, 4, 7, 9, 38, 100]) {
      for (final (name, badge) in [
        ('UnreadBadge', UnreadBadge(count: count)),
        ('RailUnreadBadge', RailUnreadBadge(count: count)),
      ]) {
        testWidgets('$name $count is centred at text scale $scale', (
          tester,
        ) async {
          final (above, below) = await margins(tester, badge, scale);
          // At desktop size a figure is a whole eight pixels, and only
          // antialiasing is left. At the phone's 11.8 it is not a whole
          // number of pixels while the line still lands on one, so no line
          // height gets it closer than about a third of a pixel either way.
          expect(
            (above - below).abs(),
            lessThanOrEqualTo(scale == 1.0 ? 0.25 : 0.75),
            reason: '$above px above the count, $below px below',
          );
        });
      }
    }
  }

  // A row whose height comes out at a half pixel centres the badge on one.
  // Drawn there, the pill's edges blur across two rows while the count
  // snaps to one, so the badge paints itself onto whole pixels instead.
  for (final (name, badge) in [
    ('UnreadBadge', const UnreadBadge(count: 2)),
    ('RailUnreadBadge', const RailUnreadBadge(count: 2)),
  ]) {
    testWidgets('$name paints on whole pixels when laid out between them', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromPalette(AppPalette.all.first, Brightness.dark),
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    children: [Positioned(left: 10.5, top: 10.5, child: badge)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).last,
      );
      late Uint8List px;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        px = data!.buffer.asUint8List();
        image.dispose();
      });
      // Down the badge's middle column, the pill's outer edges: the pixel
      // past each one is the ground, not the fill half covering it.
      final fill = AppTheme.fromPalette(
        AppPalette.all.first,
        Brightness.dark,
      ).colorScheme.primary;
      final x = (tester.getRect(find.byWidget(badge)).center.dx).floor();
      int distance(int y) {
        final i = (y * 40 + x) * 4;
        return (px[i] - (fill.r * 255).round()).abs() +
            (px[i + 1] - (fill.g * 255).round()).abs() +
            (px[i + 2] - (fill.b * 255).round()).abs();
      }

      var top = 0;
      while (distance(top) > 40) {
        top++;
      }
      var bottom = 39;
      while (distance(bottom) > 40) {
        bottom--;
      }
      expect(distance(top - 1), greaterThan(300), reason: 'top edge blurred');
      expect(
        distance(bottom + 1),
        greaterThan(300),
        reason: 'bottom edge blurred',
      );
    });
  }
}
