import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/selectable_surface.dart';
import 'package:rift/presentation/common/show_custom_dialog.dart';
import 'package:rift/presentation/screens/home/screenshare/screen_share_settings_dialog.dart';
import 'package:rift/presentation/screens/home/screenshare/widgets/share_quality_row.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

import 'support/memory_storage.dart';

/// The desktop share dialog's flow: a card is the action, the list has a page
/// of its own, and a PC with one screen is not asked which.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  const screenOne = CaptureSource(
    index: 0,
    title: 'Screen 1',
    appId: '',
    minimised: false,
  );
  const screenTwo = CaptureSource(
    index: 1,
    title: 'Screen 2',
    appId: '',
    minimised: false,
  );
  const window = CaptureSource(
    index: 0,
    title: 'Notes',
    appId: '',
    minimised: false,
  );

  /// Opens the dialog from a button, as the call bar does, and hands back
  /// where its answer lands.
  Future<List<ScreenShareSettings?>> open(
    WidgetTester tester, {
    bool picksSourceInApp = true,
    List<CaptureSource> screens = const [screenOne],
    int maxShareMbps = 0,
    ScreenShareSettings settings = const ScreenShareSettings(),
    Size size = const Size(1180, 780),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answers = <ScreenShareSettings?>[];
    final app = AppCubit()..setScreenShareSettings(settings);
    addTearDown(app.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>.value(value: app),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answers.add(
                  await showCustomDialog<ScreenShareSettings>(
                    context: context,
                    build: (_) => BlocProvider<AppCubit>.value(
                      value: app,
                      child: ScreenShareSettingsDialog(
                        maxShareMbps: maxShareMbps,
                        picksSourceInApp: picksSourceInApp,
                        listSources: ({required captureFullScreen}) async =>
                            captureFullScreen ? screens : const [window],
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Share'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    return answers;
  }

  group('a card', () {
    testWidgets('where the desktop asks, closes the dialog at once', (
      tester,
    ) async {
      final answers = await open(tester, picksSourceInApp: false);
      await tester.tap(find.text('A window'));
      await tester.pumpAndSettle();
      expect(answers.single?.captureFullScreen, isFalse);
      expect(find.text('Share your screen'), findsNothing);
    });

    testWidgets('Entire screen on one screen starts straight away', (
      tester,
    ) async {
      final answers = await open(tester);
      await tester.tap(find.text('Entire screen'));
      await tester.pumpAndSettle();
      expect(answers.single?.captureFullScreen, isTrue);
      expect(answers.single?.selectedVideoSourceTitle, 'Screen 1');
    });

    testWidgets('Entire screen on two screens asks which', (tester) async {
      final answers = await open(tester, screens: [screenOne, screenTwo]);
      await tester.tap(find.text('Entire screen'));
      await tester.pumpAndSettle();
      expect(answers, isEmpty);
      expect(find.text('Choose a screen'), findsOneWidget);

      await tester.tap(find.text('Screen 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start sharing'));
      await tester.pumpAndSettle();
      expect(answers.single?.selectedVideoSourceTitle, 'Screen 2');
    });

    testWidgets('A window lists them, the last one still picked', (
      tester,
    ) async {
      final answers = await open(
        tester,
        settings: const ScreenShareSettings(
          captureFullScreen: false,
          selectedVideoSourceTitle: 'Notes',
        ),
      );
      await tester.tap(find.text('A window'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a window'), findsOneWidget);
      await tester.tap(find.text('Start sharing'));
      await tester.pumpAndSettle();
      expect(answers.single?.selectedVideoSourceTitle, 'Notes');
    });

    testWidgets('with nothing found says so, and cannot start', (tester) async {
      await open(tester, screens: const []);
      await tester.tap(find.text('Entire screen'));
      await tester.pumpAndSettle();
      expect(find.text('No screens found.'), findsOneWidget);
    });
  });

  group('going back', () {
    testWidgets('Escape leaves the list for the first page, then the dialog', (
      tester,
    ) async {
      final answers = await open(tester);
      await tester.tap(find.text('A window'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Share your screen'), findsOneWidget);
      expect(answers, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Share your screen'), findsNothing);
      expect(answers.single, isNull);
    });

    testWidgets('Advanced comes back with what was changed there', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('120 fps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('1080p 120'), findsOneWidget);
    });
  });

  group('the quality row', () {
    test('offers 720p 60 and no 1080p 30', () {
      expect(ShareQualityRow.presets.map((p) => '${p.height} ${p.fps}'), [
        '720 30',
        '720 60',
        '1080 60',
        '1440 60',
        '2160 60',
      ]);
    });

    test('a pair nobody can press is Custom', () {
      bool preset(int height, int fps) => ShareQualityRow.isPreset(
        ScreenShareSettings(resolution: height, fps: fps),
      );
      expect(preset(1080, 60), isTrue);
      expect(preset(1080, 30), isFalse);
      expect(preset(1080, 120), isFalse);
      // 4K goes out at 60 whatever is kept for smaller pictures.
      expect(preset(2160, 120), isTrue);
    });

    testWidgets('a preset takes the Custom chip away', (tester) async {
      await open(
        tester,
        settings: const ScreenShareSettings(resolution: 1080, fps: 15),
      );
      expect(find.text('1080p 15'), findsOneWidget);
      await tester.tap(find.text('2K'));
      await tester.pumpAndSettle();
      expect(find.text('Custom'), findsNothing);
    });
  });

  group('Advanced', () {
    Future<void> openAdvanced(
      WidgetTester tester, {
      int maxShareMbps = 0,
      ScreenShareSettings settings = const ScreenShareSettings(),
    }) async {
      await open(tester, maxShareMbps: maxShareMbps, settings: settings);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
    }

    bool isGreyed(WidgetTester tester, String label) => find
        .ancestor(of: find.text(label), matching: find.byType(Opacity))
        .evaluate()
        .isNotEmpty;

    bool isSelected(WidgetTester tester, String label) => tester
        .widget<SelectableSurface>(
          find.ancestor(
            // The last: Auto's second line can read the same as a button.
            of: find.text(label).last,
            matching: find.byType(SelectableSurface),
          ),
        )
        .selected;

    testWidgets('greys 120 fps at 4K and falls to 60, keeping 120 for later', (
      tester,
    ) async {
      await openAdvanced(
        tester,
        settings: const ScreenShareSettings(resolution: 1080, fps: 120),
      );
      expect(isSelected(tester, '120 fps'), isTrue);

      await tester.tap(find.text('4K'));
      await tester.pumpAndSettle();
      expect(isGreyed(tester, '120 fps'), isTrue);
      expect(isSelected(tester, '60 fps'), isTrue);

      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();
      expect(isSelected(tester, '120 fps'), isTrue);
    });

    testWidgets('a number on the way to another does not take the box away', (
      tester,
    ) async {
      await openAdvanced(tester);
      final box = find.byType(TextField);
      await tester.enterText(box, '1');
      await tester.pump();
      await tester.enterText(box, '10');
      await tester.pump();
      expect(isSelected(tester, '10 Mbps'), isFalse);
      expect(find.text('10'), findsOneWidget);

      await tester.enterText(box, '100');
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('100 Mbps'), findsOneWidget);
    });

    testWidgets('a button empties the box', (tester) async {
      await openAdvanced(tester);
      final box = find.byType(TextField);
      await tester.enterText(box, '12');
      await tester.pump();
      await tester.tap(find.text('20 Mbps'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(box).controller!.text, isEmpty);
      expect(isSelected(tester, '20 Mbps'), isTrue);
    });

    testWidgets('emptying the box goes back to Auto', (tester) async {
      await openAdvanced(tester);
      final box = find.byType(TextField);
      await tester.enterText(box, '12');
      await tester.pump();
      await tester.enterText(box, '');
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('· 12 Mbps'), findsNothing);
    });

    testWidgets('the box takes digits, up to 100', (tester) async {
      await openAdvanced(tester);
      final box = find.byType(TextField);
      await tester.enterText(box, '4x5');
      await tester.pump();
      expect(tester.widget<TextField>(box).controller!.text, '45');
      await tester.enterText(box, '900');
      await tester.pump();
      expect(tester.widget<TextField>(box).controller!.text, '100');
    });

    testWidgets('a choice from the old ladder shows in the box', (
      tester,
    ) async {
      await openAdvanced(
        tester,
        settings: const ScreenShareSettings(bitrate: 25, bitrateChosen: true),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '25',
      );
    });

    testWidgets('over the server limit is greyed, held, and said', (
      tester,
    ) async {
      await openAdvanced(
        tester,
        maxShareMbps: 8,
        settings: const ScreenShareSettings(bitrate: 15, bitrateChosen: true),
      );
      expect(isGreyed(tester, '10 Mbps'), isTrue);
      expect(isGreyed(tester, '8 Mbps'), isFalse);
      // The stored 15 goes out at 8, so 8 is what shows.
      expect(isSelected(tester, '8 Mbps'), isTrue);
      expect(find.textContaining('limits screen shares to 8 Mbps'), findsOne);
    });
  });

  group('fits', () {
    for (final size in const [
      Size(400, 520),
      Size(800, 600),
      Size(1180, 780),
      Size(3000, 1800),
    ]) {
      testWidgets(
        'every page in a ${size.width.toInt()}x${size.height.toInt()} '
        'window',
        (tester) async {
          await open(
            tester,
            size: size,
            settings: const ScreenShareSettings(resolution: 1080, fps: 120),
          );
          expect(tester.takeException(), isNull);

          await tester.ensureVisible(find.text('Advanced'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Advanced'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();

          await tester.ensureVisible(find.text('A window'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('A window'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Choose a window'), findsOneWidget);
        },
      );
    }
  });
}
