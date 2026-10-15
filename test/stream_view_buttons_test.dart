import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/expanded_participant_tile.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/stream_view.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/stream_view_buttons.dart';

import 'support/memory_storage.dart';

void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(
    WidgetTester tester, {
    ValueChanged<StreamView>? onView,
    StreamView view = StreamView.inCall,
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
              isPaused: true,
              showWatchButton: false,
              isWatching: onView != null,
              view: view,
              onView: onView,
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
}
