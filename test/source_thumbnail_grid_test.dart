import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
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
                CaptureSource(
                  index: 0,
                  title: 'Browser',
                  appId: '',
                  minimised: false,
                ),
                CaptureSource(
                  index: 1,
                  title: 'Game',
                  appId: '',
                  minimised: true,
                ),
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

  // Three window tiles to a row once left the minimised tile's text 2 to 8 px
  // taller than its preview area: Flutter's overflow stripe, seen on Windows
  // Oct 5 2026. These are the smallest a tile gets at one, two and three to a
  // row, in the narrowest window the app allows and each step above it.
  for (final width in [300.0, 430.0, 850.0]) {
    testWidgets('a minimised tile fits in a ${width.toInt()} px list', (
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
                      CaptureSource(
                        index: 0,
                        title: 'Game',
                        appId: '',
                        minimised: true,
                      ),
                      CaptureSource(
                        index: 1,
                        title: 'Chat',
                        appId: '',
                        minimised: true,
                      ),
                      CaptureSource(
                        index: 2,
                        title: 'Music',
                        appId: '',
                        minimised: true,
                      ),
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

  // X11 lists the windows itself and has no pictures of them: the same tiles,
  // an icon and the window's app in place of the picture.
  for (final width in [300.0, 430.0, 850.0]) {
    testWidgets(
      'a tile without a picture names its app at ${width.toInt()} px',
      (tester) async {
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
                        CaptureSource(
                          index: 0,
                          title: 'A page - Mozilla Firefox',
                          appId: 'firefox',
                          minimised: false,
                        ),
                        CaptureSource(
                          index: 1,
                          title: 'Notes',
                          appId: '',
                          minimised: false,
                        ),
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
        expect(find.text('firefox'), findsOneWidget);
        expect(find.byIcon(Icons.web_asset), findsNWidgets(2));
      },
    );
  }
}
