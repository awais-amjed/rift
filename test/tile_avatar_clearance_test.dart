import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/member_avatar.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/collapsed_participant_tile.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/participant_name_badge.dart';

import 'support/memory_storage.dart';
import 'support/stub_members_cubit.dart';

/// The row of people under a watched share is 100px tall (84 on a phone),
/// and there a centred avatar sat under the name badge: a third of it
/// covered, half on a phone (Oct 5 2026). In a tile that short it moves up
/// into the room above the badge; in a larger one it stays centred.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(WidgetTester tester, Size tile) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: tile,
                child: CollapsedParticipantTile(
                  videoTrack: null,
                  isSpeaking: false,
                  name: 'Tester A',
                  userId: 'user-a',
                  isMicEnabled: true,
                  isMuted: false,
                  isScreenshare: false,
                  showWatchButton: false,
                  isWatching: false,
                  onWatch: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect avatar(WidgetTester tester) => tester.getRect(find.byType(MemberAvatar));
  Rect badge(WidgetTester tester) =>
      tester.getRect(find.byType(ParticipantNameBadge));

  for (final (what, tile) in [
    ('the row under a share', const Size(178, 100)),
    ('the same row on a phone', const Size(149, 84)),
  ]) {
    testWidgets('in $what the badge covers none of the avatar', (tester) async {
      await pump(tester, tile);
      final a = avatar(tester);
      expect(a.bottom, lessThanOrEqualTo(badge(tester).top), reason: '$a');
      // Still a face, not a dot.
      expect(a.height, greaterThanOrEqualTo(tile.height * 0.35));
    });
  }

  testWidgets('a tile with room keeps its avatar centred', (tester) async {
    await pump(tester, const Size(640, 360));
    final tile = tester.getRect(find.byType(CollapsedParticipantTile));
    final a = avatar(tester);
    expect(a.center.dy, closeTo(tile.center.dy, 0.5));
    expect(a.bottom, lessThanOrEqualTo(badge(tester).top));
  });
}
