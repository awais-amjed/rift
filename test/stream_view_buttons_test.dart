import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/expanded_participant_tile.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/stream_view.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/stream_view_buttons.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/stream_volume_button.dart';

import 'support/memory_storage.dart';

/// Records the mutes asked for, and plays nothing.
class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit() : super(const LiveKitState());

  final mutes = <(String, bool)>[];

  @override
  void setMuteFor(String key, bool muted) => mutes.add((key, muted));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _StubLiveKitCubit livekit;
  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    livekit = _StubLiveKitCubit();
  });

  Future<void> pump(
    WidgetTester tester, {
    ValueChanged<StreamView>? onView,
    StreamView view = StreamView.inCall,
    String? soundKey,
  }) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
          BlocProvider<LiveKitCubit>.value(value: livekit),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ExpandedParticipantTile(
              videoTrack: null,
              name: 'Lana',
              userId: 'user-1',
              isMicEnabled: false,
              isMuted: false,
              isScreenshare: true,
              isPaused: true,
              showWatchButton: false,
              isWatching: onView != null,
              view: view,
              onView: onView,
              soundKey: soundKey,
              showOverlays: true,
              statsPinned: false,
              onActivity: () {},
              onWatch: () {},
              onStatsPinnedChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a watched stream offers edge to edge and full screen', (
    tester,
  ) async {
    final asked = <StreamView>[];
    await pump(tester, onView: asked.add);
    expect(find.byTooltip('Edge to edge'), findsOneWidget);
    expect(find.byTooltip('Full screen'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.fit_screen_outlined));
    await tester.tap(find.byIcon(Icons.fullscreen));
    expect(asked, [StreamView.edgeToEdge, StreamView.fullscreen]);
  });

  testWidgets('full screen offers the way out, and edge to edge beside it', (
    tester,
  ) async {
    await pump(tester, onView: (_) {}, view: StreamView.fullscreen);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect(find.byTooltip('Edge to edge'), findsOneWidget);
  });

  testWidgets('edge to edge offers the way out, and full screen beside it', (
    tester,
  ) async {
    await pump(tester, onView: (_) {}, view: StreamView.edgeToEdge);
    expect(find.byTooltip('Exit edge to edge'), findsOneWidget);
    expect(find.byTooltip('Full screen'), findsOneWidget);
  });

  testWidgets('nothing to watch alone, no buttons', (tester) async {
    await pump(tester);
    expect(find.byType(StreamViewButtons), findsNothing);
  });

  testWidgets('a stream with sound has its volume before the view buttons', (
    tester,
  ) async {
    await pump(tester, onView: (_) {}, soundKey: 'share-key');
    final volume = tester.getCenter(find.byType(StreamVolumeButton));
    final edge = tester.getCenter(find.byTooltip('Edge to edge'));
    expect(volume.dx, lessThan(edge.dx));

    await tester.tap(
      find.byTooltip('Mute stream'),
      kind: PointerDeviceKind.mouse,
    );
    expect(livekit.mutes, [('share-key', true)]);
  });

  testWidgets('pointing at the speaker slides out the volume', (tester) async {
    await pump(tester, onView: (_) {}, soundKey: 'share-key');
    expect(find.byType(Slider), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Mute stream')));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('a finger opens the volume first, and mutes after', (
    tester,
  ) async {
    await pump(tester, onView: (_) {}, soundKey: 'share-key');
    await tester.tap(
      find.byTooltip('Mute stream'),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(livekit.mutes, isEmpty);

    await tester.tap(
      find.byTooltip('Mute stream'),
      kind: PointerDeviceKind.touch,
    );
    expect(livekit.mutes, [('share-key', true)]);
  });

  testWidgets('a stream with no sound has no volume', (tester) async {
    await pump(tester, onView: (_) {});
    expect(find.byType(StreamVolumeButton), findsNothing);
  });
}
