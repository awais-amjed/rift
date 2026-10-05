import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/screenshare/widgets/source_thumbnail_grid.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

import 'support/memory_storage.dart';

/// A minimised window has no picture, and is listed anyway: a minimised game
/// is what people go looking for. Its tile says why there is no picture and
/// when the share of it will start.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('a minimised window says its share starts when it is opened', (
    tester,
  ) async {
    CaptureSource? picked;
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: SourceThumbnailGrid(
              sources: const [
                CaptureSource(index: 0, title: 'Browser', minimised: false),
                CaptureSource(index: 1, title: 'Game', minimised: true),
              ],
              selectedIndex: 0,
              thumbnails: const {},
              captureFullScreen: false,
              onChanged: (source) => picked = source,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Starts when you open\u00A0it'), findsOneWidget);
    await tester.tap(find.text('Game'));
    expect(picked?.index, 1);
  });

  // The share dialog's column is about 288 px wide, three window tiles to a
  // row, which left the minimised tile's text 2 to 8 px taller than its
  // preview area: Flutter's overflow stripe, seen on Windows Oct 5 2026.
  for (final width in [240.0, 288.0, 340.0]) {
    testWidgets('a minimised tile fits in a ${width.toInt()} px dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        BlocProvider<ThemeCubit>(
          create: (_) => ThemeCubit(),
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: SourceThumbnailGrid(
                    sources: const [
                      CaptureSource(index: 0, title: 'Game', minimised: true),
                      CaptureSource(index: 1, title: 'Chat', minimised: true),
                      CaptureSource(index: 2, title: 'Music', minimised: true),
                    ],
                    selectedIndex: 0,
                    thumbnails: const {},
                    captureFullScreen: false,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Minimised'), findsNWidgets(3));
    });
  }
}
