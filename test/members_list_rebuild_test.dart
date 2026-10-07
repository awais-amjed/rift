import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/member_page.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/members_sidebar/widgets/member_row.dart';
import 'package:rift/presentation/screens/home/members_sidebar/widgets/members_sidebar_list.dart';

import 'support/memory_storage.dart';
import 'support/rebuild_counter.dart';
import 'support/stub_members_cubit.dart';

/// How much of the member list somebody coming online redraws.
///
/// Presence changes all day on a busy server. The list used to rebuild every
/// row on screen for each one, and for every move between voice channels too,
/// which changes nothing it shows.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  final members = [
    for (var i = 0; i < 12; i++)
      ServerMember(
        id: 'm$i',
        username: 'm$i',
        displayName: 'Member ${i.toString().padLeft(2, '0')}',
        permissions: const UserPermissions(),
      ),
  ];
  final roster = ServerMembersState(
    people: MemberPage(members: members, hasMore: false),
    peopleCount: members.length,
    loaded: true,
  );
  const appState = AppState();

  Future<void> pump(WidgetTester tester, Set<String> online) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 2000,
              child: MembersSidebarList(
                key: const ValueKey('list'),
                appState: appState,
                roster: roster,
                onlineIds: online,
                myId: 'm0',
                onLoadMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('somebody coming online redraws their row only', (tester) async {
    await pump(tester, {'m0', 'm1'});
    expect(find.byType(MemberRow), findsNWidgets(12));

    final counts = await countRebuilds(() => pump(tester, {'m0', 'm1', 'm7'}));
    expect(counts[MemberRow], 1);
    // And it moved: Online now holds three.
    expect(find.text('ONLINE — 3'), findsOneWidget);
  });

  testWidgets('nothing changing redraws no row', (tester) async {
    await pump(tester, {'m0', 'm1'});
    final counts = await countRebuilds(() => pump(tester, {'m0', 'm1'}));
    expect(counts[MemberRow], isNull);
  });
}
