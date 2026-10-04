import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/avatar_placeholder.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/expanded_participant_tile.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/share_paused_notice.dart';

import 'support/memory_storage.dart';

/// A share started on a minimised window is up before it has a picture: it
/// waits for the sharer to open the window. Whoever is watching is told it is
/// paused, rather than shown the sharer's avatar as if the stream were broken.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(
    WidgetTester tester, {
    required bool isPaused,
    required bool showWatchButton,
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
              name: 'Win VM',
              userId: 'user-1',
              isMicEnabled: false,
              isMuted: false,
              isScreenshare: true,
              isPaused: isPaused,
              showWatchButton: showWatchButton,
              isWatching: false,
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

  testWidgets('a watched share with no picture yet says it is paused', (
    tester,
  ) async {
    await pump(tester, isPaused: true, showWatchButton: false);
    expect(find.byType(SharePausedNotice), findsOneWidget);
    expect(find.byType(AvatarPlaceholder), findsNothing);
  });

  testWidgets('an unopened one still offers to be watched', (tester) async {
    await pump(tester, isPaused: true, showWatchButton: true);
    expect(find.byType(SharePausedNotice), findsNothing);
    expect(find.text('Watch stream'), findsOneWidget);
  });
}
