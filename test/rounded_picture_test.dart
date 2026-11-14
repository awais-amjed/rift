import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/rounded_picture.dart';
import 'package:rift/presentation/common/rounded_square_image.dart';

import 'helpers/memory_storage.dart';

/// Every avatar and icon picture is drawn as a plain square whose corners are
/// cut into its pixels, decoded at the size it is drawn (see
/// [RoundedPicture]).
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  const green = Color(0xFF22AA44);
  const red = Color(0xFFAA2244);
  final shot = GlobalKey();

  Widget host(Widget child) => BlocProvider<ThemeCubit>(
    create: (_) => ThemeCubit(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(key: shot, child: child),
      ),
    ),
  );

  Future<Uint8List> png(WidgetTester tester, Color color) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(const Rect.fromLTWH(0, 0, 4, 2), Paint()..color = color);
      final image = await recorder.endRecording().toImage(4, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  // Decoding and cutting the corners happen off the test's fake clock, in
  // several steps.
  Future<void> decode(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  /// The colour drawn at ([x], [y]) inside the picture's box.
  Future<Color> pixel(WidgetTester tester, int x, int y) async {
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData();
      return (data!, image.width);
    });
    final (data, width) = bytes!;
    final i = (y * width + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  Widget picture(Uint8List bytes) => RoundedPicture(
    image: MemoryImage(bytes),
    size: 28,
    radius: 7.84,
    fallback: const Text('L'),
  );

  testWidgets('draws the picture in a rounded square, with no clip', (
    tester,
  ) async {
    await tester.pumpWidget(host(picture(await png(tester, green))));
    await decode(tester);

    expect(find.text('L'), findsNothing);
    expect(await pixel(tester, 14, 14), green);
    // The corner is outside the rounded shape.
    expect((await pixel(tester, 0, 0)).a, 0);
    // A pixel on the curve is partly kept: the edge is smooth, not stepped.
    // Its colour is faded with it (the bytes are premultiplied), not twice.
    final edge = await pixel(tester, 2, 2);
    final alpha = (edge.a * 255).round();
    expect(alpha, inInclusiveRange(150, 230));
    expect((edge.g * 255).round(), closeTo(0xAA * alpha / 255, 2));
    for (final clip in [ClipRRect, ClipPath, ClipRect, DecoratedBox]) {
      expect(
        find.descendant(
          of: find.byType(RoundedPicture),
          matching: find.byType(clip),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('keeps the old picture until the new one has decoded', (
    tester,
  ) async {
    final first = await png(tester, green);
    final second = await png(tester, red);

    await tester.pumpWidget(host(picture(first)));
    await decode(tester);
    await tester.pumpWidget(host(picture(second)));

    expect(find.text('L'), findsNothing);
    expect(await pixel(tester, 14, 14), green);

    await decode(tester);
    expect(await pixel(tester, 14, 14), red);
  });

  testWidgets('a picture that cannot be decoded shows the fallback', (
    tester,
  ) async {
    await tester.pumpWidget(host(picture(Uint8List.fromList([1, 2, 3, 4]))));
    await decode(tester);

    expect(find.text('L'), findsOneWidget);
  });

  test('decodes a picture so its shorter side is the drawn size', () {
    (int?, int?) of(ui.TargetImageSize? s) => (s?.width, s?.height);
    const cover = RoundedSquareImage.coverDecodeSize;

    // A square avatar, shrunk to the chip.
    expect(of(cover(512, 512, 56)), (56, 56));
    // A wide one keeps its shape, its height the chip's.
    expect(of(cover(1000, 500, 56)), (112, 56));
    expect(of(cover(300, 900, 56)), (56, 168));
    // Never enlarged.
    expect(cover(40, 40, 56), isNull);
    expect(cover(400, 56, 56), isNull);
  });

  test('keeps each pixel by how much of it is inside the corners', () {
    const coverage = RoundedSquareImage.coverage;

    // Inside, and along the straight edges.
    expect(coverage(28, 28, 56, 12), 1);
    expect(coverage(0.5, 28, 56, 12), 1);
    expect(coverage(28, 55.5, 56, 12), 1);
    // The very corner is cut away, at all four.
    for (final (x, y) in [(0.5, 0.5), (55.5, 0.5), (0.5, 55.5), (55.5, 55.5)]) {
      expect(coverage(x, y, 56, 12), 0);
    }
    // On the curve, in between, the same at each corner.
    final curve = coverage(3.5, 3.5, 56, 12);
    expect(curve, inExclusiveRange(0, 1));
    expect(coverage(52.5, 52.5, 56, 12), curve);
    // A radius past half the side is a circle.
    expect(coverage(0.5, 28, 56, 40), 1);
    expect(coverage(4.5, 4.5, 56, 40), 0);
  });

  test('fades corner pixels in all four channels', () {
    const side = 8;
    final rgba = Uint8List.fromList(List.filled(side * side * 4, 200));
    RoundedSquareImage.cutCorners(rgba, side, 3);

    int at(int x, int y, int channel) => rgba[(y * side + x) * 4 + channel];
    expect([for (var c = 0; c < 4; c++) at(0, 0, c)], [0, 0, 0, 0]);
    expect([for (var c = 0; c < 4; c++) at(4, 4, c)], [200, 200, 200, 200]);
    final kept = at(1, 0, 3);
    expect(kept, inExclusiveRange(0, 200));
    expect([for (var c = 0; c < 3; c++) at(1, 0, c)], [kept, kept, kept]);
  });
}
