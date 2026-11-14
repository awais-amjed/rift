import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/rounded_picture.dart';

import 'helpers/memory_storage.dart';

/// Every avatar and icon picture is the fill of a rounded square, with no
/// clip, decoded at the size it is drawn (see [RoundedPicture]).
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

  // Decoding happens off the test's fake clock.
  Future<void> decode(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
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

  testWidgets('fills a rounded square with the picture, with no clip', (
    tester,
  ) async {
    await tester.pumpWidget(host(picture(await png(tester, green))));
    await decode(tester);

    expect(find.text('L'), findsNothing);
    expect(await pixel(tester, 14, 14), green);
    // The corner is outside the rounded shape.
    expect((await pixel(tester, 0, 0)).a, 0);
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

    // A square avatar, shrunk to the chip.
    expect(of(RoundedPicture.coverDecodeSize(512, 512, 56)), (56, 56));
    // A wide one keeps its shape, its height the chip's.
    expect(of(RoundedPicture.coverDecodeSize(1000, 500, 56)), (112, 56));
    expect(of(RoundedPicture.coverDecodeSize(300, 900, 56)), (56, 168));
    // Never enlarged.
    expect(RoundedPicture.coverDecodeSize(40, 40, 56), isNull);
    expect(RoundedPicture.coverDecodeSize(400, 56, 56), isNull);
  });
}
