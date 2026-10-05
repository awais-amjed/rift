import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/screenshare/widgets/share_options.dart';

import 'support/memory_storage.dart';

/// The share dialog's options: codec and bitrate wait behind "Advanced
/// settings", and the whole block fits a narrow dialog as well as a wide one.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(
    WidgetTester tester,
    ScreenShareSettings settings, {
    double width = 600,
    ValueChanged<bool>? onAdvancedToggled,
  }) => tester.pumpWidget(
    BlocProvider<ThemeCubit>(
      create: (_) => ThemeCubit(),
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: ShareOptions(
                  settings: settings,
                  onChanged: (_) {},
                  maxShareMbps: 8,
                  audioSources: const [],
                  loadingAudioSources: false,
                  onRefreshAudioSources: () async {},
                  onAudioToggle: () {},
                  onAdvancedToggled: onAdvancedToggled ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('codec and bitrate start hidden behind Advanced settings', (
    tester,
  ) async {
    bool? toggled;
    await pump(
      tester,
      const ScreenShareSettings(),
      onAdvancedToggled: (open) => toggled = open,
    );
    expect(find.text('RESOLUTION'), findsOneWidget);
    expect(find.text('CODEC'), findsNothing);
    expect(find.text('BITRATE'), findsNothing);

    await tester.tap(find.text('Advanced settings'));
    expect(toggled, isTrue);
  });

  testWidgets('opened, they show Auto and what it picked', (tester) async {
    await pump(tester, const ScreenShareSettings(showsAdvanced: true));
    await tester.pumpAndSettle();
    expect(find.text('CODEC'), findsOneWidget);
    expect(find.text('Auto (VP9)'), findsOneWidget);
    // Auto's 10 Mbps for 1080p60 VP9, held to the server's 8.
    expect(find.text('Auto (8 Mbps)'), findsOneWidget);
    expect(find.textContaining('limits screen shares to 8 Mbps'), findsOne);
  });

  for (final width in [320.0, 900.0]) {
    testWidgets('fits a ${width.toInt()} px dialog, opened', (tester) async {
      await pump(
        tester,
        const ScreenShareSettings(showsAdvanced: true),
        width: width,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
