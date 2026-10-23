import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/rounded_picture.dart';

import 'helpers/memory_storage.dart';

/// Every avatar and icon picture is an [Image] cut by a rounded clip, so
/// Flutter does the scaling (see [RoundedPicture]).
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Widget host(Widget child) => BlocProvider<ThemeCubit>(
    create: (_) => ThemeCubit(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );

  testWidgets('draws the picture inside a rounded clip', (tester) async {
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 2),
        Paint()..color = const Color(0xFF22AA44),
      );
      final image = await recorder.endRecording().toImage(4, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    await tester.pumpWidget(
      host(RoundedPicture(image: MemoryImage(png!), size: 28, radius: 7.84)),
    );
    // Decoding happens off the test's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(RoundedPicture),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(clip.borderRadius, BorderRadius.circular(7.84));
    expect(
      find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byType(RawImage),
      ),
      findsOneWidget,
    );
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('L'), findsOneWidget);
  });
}
