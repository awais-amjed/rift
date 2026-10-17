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
import 'package:rift/presentation/common/loading_dots.dart';
import 'package:rift/presentation/screens/home/members_sidebar/widgets/member_row.dart';
import 'package:rift/presentation/screens/home/members_sidebar/widgets/members_sidebar_list.dart';

import 'support/memory_storage.dart';
import 'support/stub_members_cubit.dart';

/// The member list before presence has answered.
///
/// Opening a server drew all of its members under "Offline", dimmed, for as
/// long as presence took to answer, which on a slow server was long enough to
/// believe. Not yet known is not offline.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  final members = [
    for (var i = 0; i < 6; i++)
      ServerMember(
        id: 'm$i',
        username: 'm$i',
        displayName: 'Member $i',
        permissions: const UserPermissions(),
      ),
  ];
  final roster = ServerMembersState(
    people: MemberPage(members: members, hasMore: false),
    peopleCount: members.length,
    loaded: true,
  );

  Future<void> pump(
    WidgetTester tester, {
    required bool known,
    Set<String> online = const {},
  }) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 1200,
              child: MembersSidebarList(
                appState: const AppState(),
                roster: roster,
                onlineIds: online,
                onlineKnown: known,
                myId: 'm0',
                onLoadMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The opacity each row is drawn at.
  List<double> rowOpacities(WidgetTester tester) => [
    for (final row in find.byType(MemberRow).evaluate())
      tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byWidget(row.widget),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
  ];

  testWidgets('before presence answers, nobody is listed as offline', (
    tester,
  ) async {
    await pump(tester, known: false);

    expect(find.text('MEMBERS — 6'), findsOneWidget);
    expect(find.textContaining('OFFLINE'), findsNothing);
    expect(find.textContaining('ONLINE'), findsNothing);
    expect(find.byType(LoadingDots), findsOneWidget);
    expect(rowOpacities(tester), everyElement(1.0));
  });

  testWidgets('once it answers, the list splits as before', (tester) async {
    await pump(tester, known: false);
    await pump(tester, known: true, online: {'m0', 'm3'});

    expect(find.text('ONLINE — 2'), findsOneWidget);
    expect(find.text('OFFLINE — 4'), findsOneWidget);
    expect(find.byType(LoadingDots), findsNothing);
    expect(rowOpacities(tester).where((o) => o < 1), hasLength(4));
  });
}
