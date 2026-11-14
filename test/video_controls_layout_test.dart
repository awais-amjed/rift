import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/services/attachment_loader.dart';
import 'package:rift/presentation/common/chat/attachments/video/clip_playback.dart';
import 'package:rift/presentation/common/chat/attachments/video/widgets/video_controls.dart';

class _StubAppCubit extends Cubit<AppState> implements AppCubit {
  _StubAppCubit() : super(const AppState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The strip under a playing video is laid out where nothing bounds its
/// height: at the foot of the card, and of the full-screen page. A child
/// that sizes itself to what it is offered (an `OverflowBox`) took that
/// endless height, and the whole strip never drew.
void main() {
  ClipPlayback playback() => ClipPlayback(
    attachment: const Attachment(
      id: 'a',
      kind: AttachmentKind.video,
      name: 'clip.mp4',
      mime: 'video/mp4',
      size: 1,
      storagePath: 'p',
      keyB64: '',
      nonceB64: '',
      durationMs: 60000,
    ),
    loader: AttachmentLoader(
      load: (_) async => null,
      save: (_, _, {onProgress}) => throw UnimplementedError(),
    ),
  );

  for (final fullscreen in [false, true]) {
    for (final width in [120.0, 180.0, 260.0, 360.0, 480.0, 1280.0]) {
      testWidgets('lays out at ${width.toInt()} px'
          '${fullscreen ? ', full screen' : ''}, volume open', (tester) async {
        await tester.pumpWidget(
          BlocProvider<AppCubit>(
            create: (_) => _StubAppCubit(),
            child: MaterialApp(
              home: Center(
                child: SizedBox(
                  width: width,
                  height: 300,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoControls(
                          playback: playback(),
                          onToggle: () {},
                          big: fullscreen,
                          fullscreen: fullscreen,
                          onFullscreen: () {},
                          onExpand: fullscreen ? null : () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final strip = tester.getSize(find.byType(VideoControls));
        expect(strip.height, lessThan(120));
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(
          find.byIcon(Icons.fullscreen_rounded),
          findsNWidgets(fullscreen ? 0 : 1),
        );
        expect(
          find.byIcon(Icons.open_in_full_rounded),
          findsNWidgets(!fullscreen && width >= 200 ? 1 : 0),
        );
        if (width >= 340) expect(find.textContaining('1:00'), findsOneWidget);
        final speaker = find.byIcon(Icons.volume_up_rounded);
        if (width < 140) return expect(speaker, findsNothing);

        // Over the speaker, the volume stands up above it, over the
        // picture rather than in the strip, which keeps its height.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(speaker));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('100%'), findsOneWidget);
        expect(tester.getSize(find.byType(VideoControls)), strip);
        final figure = tester.getCenter(find.text('100%'));
        expect(figure.dy, lessThan(tester.getTopLeft(speaker).dy));

        // And goes a moment after the pointer leaves.
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsNothing);
        await mouse.removePointer();
      });
    }
  }
}
