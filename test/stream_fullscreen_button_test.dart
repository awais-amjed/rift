import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/expanded_participant_tile.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/stream_fullscreen_button.dart';

import 'support/memory_storage.dart';

/// A watched stream has a full-screen button in the corner opposite its
/// badges, and the same button takes a full-screen stream back out.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onFullscreen,
    bool isFullscreen = false,
  }) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
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
              // Paused, so the stage draws a notice rather than an avatar,
              // which would need the members cubit.
              isPaused: true,
              showWatchButton: false,
              isWatching: onFullscreen != null,
              isFullscreen: isFullscreen,
              onFullscreen: onFullscreen,
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

  testWidgets('a watched stream opens full screen from its corner', (
    tester,
  ) async {
    var opened = 0;
    await pump(tester, onFullscreen: () => opened++);
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    expect(find.byTooltip('Full screen'), findsOneWidget);
    await tester.tap(find.byType(StreamFullscreenButton));
    expect(opened, 1);
  });

  testWidgets('full screen offers the way back out', (tester) async {
    await pump(tester, onFullscreen: () {}, isFullscreen: true);
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
  });

  testWidgets('nothing to put full screen, no button', (tester) async {
    await pump(tester);
    expect(find.byType(StreamFullscreenButton), findsNothing);
  });
}
