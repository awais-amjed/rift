import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/rounded_picture.dart';

import 'helpers/memory_storage.dart';

/// Every avatar and icon picture is a rounded decoration, not a clip, and
/// keeps its last picture until the next has decoded (see [RoundedPicture]).
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Widget host(Widget child) => BlocProvider<ThemeCubit>(
    create: (_) => ThemeCubit(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
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

  BoxDecoration? decoration(WidgetTester tester) {
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(RoundedPicture),
        matching: find.byType(DecoratedBox),
      ),
    );
    return boxes.isEmpty ? null : boxes.single.decoration as BoxDecoration;
  }

  testWidgets('draws the picture as a rounded decoration, unclipped', (
    tester,
  ) async {
    final bytes = await png(tester, const Color(0xFF22AA44));
    await tester.pumpWidget(
      host(
        RoundedPicture(
          image: MemoryImage(bytes),
          size: 28,
          radius: 7.84,
          fallback: const Text('L'),
        ),
      ),
    );
    await decode(tester);

    final box = decoration(tester)!;
    expect(box.borderRadius, BorderRadius.circular(7.84));
    expect(box.image!.image, MemoryImage(bytes));
    expect(box.image!.fit, BoxFit.cover);
    // Nothing under it to show through a clear part of the picture.
    expect(find.text('L'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(RoundedPicture),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
  });

  testWidgets('keeps the old picture until the new one has decoded', (
    tester,
  ) async {
    final first = await png(tester, const Color(0xFF22AA44));
    final second = await png(tester, const Color(0xFFAA2244));
    Widget picture(Uint8List bytes) => host(
      RoundedPicture(
        image: MemoryImage(bytes),
        size: 28,
        radius: 7.84,
        fallback: const Text('L'),
      ),
    );

    await tester.pumpWidget(picture(first));
    await decode(tester);
    await tester.pumpWidget(picture(second));

    expect(decoration(tester)!.image!.image, MemoryImage(first));
    expect(find.text('L'), findsNothing);

    await decode(tester);
    expect(decoration(tester)!.image!.image, MemoryImage(second));
  });

  testWidgets('a picture that cannot be decoded shows the fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        RoundedPicture(
          image: MemoryImage(Uint8List.fromList([1, 2, 3, 4])),
          size: 28,
          radius: 7.84,
          fallback: const Text('L'),
        ),
      ),
    );
    await decode(tester);

    expect(find.text('L'), findsOneWidget);
    expect(decoration(tester), isNull);
  });
}
