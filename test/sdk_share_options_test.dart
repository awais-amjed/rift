import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/phone_share_publish.dart';
import 'package:rift/presentation/screens/home/screenshare/widgets/sdk_share_options.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

import 'support/memory_storage.dart';

/// A phone's or a browser's share options fit its dialog, and name what will
/// go out.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(
    WidgetTester tester,
    ScreenShareSettings settings, {
    double width = 280,
    List<VideoCodec> codecs = const [
      VideoCodec.vp8,
      VideoCodec.h264,
      VideoCodec.vp9,
    ],
    bool offersSound = false,
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
                child: SdkShareOptions(
                  settings: settings,
                  codecs: codecs,
                  autoCodec: PhoneShare.autoCodec(codecs),
                  offersSound: offersSound,
                  resolutions: const [480, 720, 1080],
                  frameRates: const [15, 30, 60],
                  onChanged: (_) {},
                  onAdvancedToggled: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  const opened = ScreenShareSettings(resolution: 1080, fps: 30);

  testWidgets('codec and bitrate wait behind Advanced settings', (
    tester,
  ) async {
    await pump(tester, opened);
    expect(find.text('CODEC'), findsNothing);
    expect(find.text('BITRATE'), findsNothing);

    await pump(tester, opened.copyWith(showsAdvanced: true));
    await tester.pumpAndSettle();
    expect(find.text('CODEC'), findsOneWidget);
    expect(find.text('BITRATE'), findsOneWidget);
  });

  testWidgets('every option fits a narrow phone, opened or not', (
    tester,
  ) async {
    await pump(tester, opened.copyWith(showsAdvanced: true), width: 240);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Auto names what this phone would send', (tester) async {
    await pump(tester, opened.copyWith(showsAdvanced: true));
    await tester.pumpAndSettle();
    expect(find.text('Auto (H264)'), findsOneWidget);
    expect(find.text('Auto (11 Mbps)'), findsOneWidget);

    await pump(
      tester,
      opened.copyWith(showsAdvanced: true),
      codecs: const [VideoCodec.vp8],
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto (VP8)'), findsOneWidget);
  });

  testWidgets('only a browser offers sound, and says where else to tick it', (
    tester,
  ) async {
    await pump(tester, opened);
    expect(find.text('Share sound'), findsNothing);

    await pump(tester, opened.copyWith(shareAudio: true), offersSound: true);
    expect(find.text('Share sound'), findsOneWidget);
    expect(find.textContaining('picker'), findsOneWidget);

    await pump(tester, opened.copyWith(shareAudio: false), offersSound: true);
    expect(find.text('Share sound'), findsOneWidget);
    expect(find.textContaining('picker'), findsNothing);
  });
}
