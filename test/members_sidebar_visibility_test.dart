import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/data/classes/member_page.dart';
import 'package:rift/logic/cubits/channel_presence/channel_presence_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/members_sidebar/members_sidebar.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/sidebar_resize_handle.dart';

import 'shell_scope_harness.dart';

/// In-memory stand-in so the HydratedCubits can be built in tests.
class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// Presence with nobody online — enough to render the panel's chrome, which is
/// what the collapse animation lays out.
class _StubPresenceCubit extends Cubit<ChannelPresenceState>
    implements ChannelPresenceCubit {
  _StubPresenceCubit() : super(const ChannelPresenceState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No server selected — the panel then renders its chrome and an empty roster,
/// which is exactly the layout the animation moves.
class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit() : super(const ServerState());

  @override
  Future<({bool success, MemberPage? page, String? error})> listMembers({
    String? serverId,
    String? channelId,
    bool? bots,
    bool? banned = false,
    ({String name, String id})? after,
    int limit = MemberPage.pageSize,
  }) async => (success: true, page: MemberPage.empty, error: null);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A roster that has already loaded and is empty — no realtime connection, so
/// the layout test doesn't need a server to talk to.
class _StubMembersCubit extends Cubit<ServerMembersState>
    implements ServerMembersCubit {
  _StubMembersCubit() : super(ServerMembersState(loaded: true));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  AppCubit appCubit, {
  bool floating = false,
  double windowWidth = 1400,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      // Width is what picks the layout mode, and the mode decides whether the
      // panel carries gutters. Defaults to a desktop.
      data: MediaQueryData(size: Size(windowWidth, 800)),
      child: MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
              BlocProvider<AppCubit>.value(value: appCubit),
              BlocProvider<ChannelPresenceCubit>(
                create: (_) => _StubPresenceCubit(),
              ),
              BlocProvider<ServerCubit>(create: (_) => _StubServerCubit()),
              BlocProvider<ServerMembersCubit>(
                create: (_) => _StubMembersCubit(),
              ),
            ],
            // Openness is passed in rather than read by the panel, so the
            // harness has to do what the shell does: hand it the flag.
            child: withShellScope(
              BlocBuilder<AppCubit, AppState>(
                builder: (context, appState) => Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    MembersSidebar(
                      open: appState.membersSidebarOpen,
                      floating: floating,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  // The panel's width animates while `membersSidebarOpen` flips at once, so a
  // naive implementation lays the full-width content out at a few pixels for
  // the whole animation — a burst of RenderFlex overflows on every toggle.
  // Pumping mid-animation is the only way to catch that, and hiding it fully
  // makes it worse than collapsing did: the width now passes through zero.
  testWidgets('hiding and showing never overflows mid-animation', (
    tester,
  ) async {
    final appCubit = AppCubit();
    addTearDown(appCubit.close);
    await _pump(tester, appCubit);
    await tester.pumpAndSettle();

    for (var round = 0; round < 2; round++) {
      for (final _ in [0, 1]) {
        appCubit.toggleMembersSidebar();
        // Step through the animation rather than settling past it.
        for (var ms = 0; ms <= K.sidebarMotion.inMilliseconds + 40; ms += 20) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(
            tester.takeException(),
            isNull,
            reason:
                'overflow while animating to '
                '${appCubit.state.membersSidebarOpen ? "open" : "hidden"}',
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  // Hidden means gone, not narrow. It used to leave a 42px strip behind for a
  // reopen button; that button is an EdgeTab over the content now, so the panel
  // owes the layout nothing at all — including the gutter beside it, which
  // would otherwise hang off the right of the window.
  testWidgets('settles at full width, then at nothing', (tester) async {
    final appCubit = AppCubit();
    addTearDown(appCubit.close);
    await _pump(tester, appCubit);
    await tester.pumpAndSettle();

    double panelWidth() => tester.getSize(find.byType(MembersSidebar)).width;

    expect(appCubit.state.membersSidebarOpen, isTrue);
    expect(panelWidth(), K.membersSidebarWidth + K.panelGutter);

    appCubit.toggleMembersSidebar();
    await tester.pumpAndSettle();
    expect(panelWidth(), 0);

    appCubit.toggleMembersSidebar();
    await tester.pumpAndSettle();
    expect(panelWidth(), K.membersSidebarWidth + K.panelGutter);
  });

  // Overlaid, the panel has content on both sides of it rather than only the
  // chat to its left, so it carries a gutter on both. Getting this wrong is
  // not a crash but a panel welded to the window edge, which is exactly the
  // sort of thing that survives a review.
  // The panel's declared width and what its Row actually lays out have to
  // agree, and they are computed in two different places. When the gutters
  // went away on a phone, one of the two kept them: the box stayed the width
  // of the panel while the Row inside still asked for the panel plus 20px,
  // which is an overflow stripe down the middle of the drawer.
  testWidgets('a phone drawer is the panel and nothing else', (tester) async {
    final appCubit = AppCubit();
    addTearDown(appCubit.close);
    await _pump(tester, appCubit, floating: true, windowWidth: 390);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(MembersSidebar)).width,
      K.membersSidebarWidth,
      reason: 'no gutters survive on a phone',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating reserves a gutter on both sides', (tester) async {
    final appCubit = AppCubit();
    addTearDown(appCubit.close);
    await _pump(tester, appCubit, floating: true);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(MembersSidebar)).width,
      K.membersSidebarWidth + K.panelGutter * 2,
    );

    appCubit.toggleMembersSidebar();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MembersSidebar)).width, 0);
    expect(tester.takeException(), isNull);
  });

  // The handle is looked up through offstage widgets: the panel's content
  // sits in an OverflowBox pinned wider than the animating container, which
  // the default finder treats as offstage even when it is fully on screen.
  // And the cubit is hydrated from a store the tests above share, so the
  // panel is opened explicitly rather than assumed open.
  group('resizing', () {
    AppCubit openCubit() {
      final cubit = AppCubit();
      if (!cubit.state.membersSidebarOpen) cubit.toggleMembersSidebar();
      return cubit;
    }

    testWidgets('dragging the handle left widens the panel', (tester) async {
      final appCubit = openCubit();
      await _pump(tester, appCubit);
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byType(MembersSidebar)).width;

      await tester.drag(
        find.byType(SidebarResizeHandle, skipOffstage: false),
        const Offset(-100, 0),
      );
      await tester.pumpAndSettle();

      // Less than the full 100: the first few pixels are the drag slop.
      expect(
        tester.getSize(find.byType(MembersSidebar)).width,
        greaterThan(before + 60),
      );
      expect(
        appCubit.state.membersSidebarWidth,
        greaterThan(K.membersSidebarWidth + 60),
      );
    });

    testWidgets('a double-click puts it back', (tester) async {
      final appCubit = openCubit()
        ..setMembersSidebarWidth(K.membersSidebarWidth + 80);
      await _pump(tester, appCubit);
      await tester.pumpAndSettle();

      final handle = find.byType(SidebarResizeHandle, skipOffstage: false);
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handle);
      await tester.pumpAndSettle();

      expect(appCubit.state.membersSidebarWidth, K.membersSidebarWidth);
    });

    testWidgets('it stops at the floor', (tester) async {
      final appCubit = openCubit();
      await _pump(tester, appCubit);
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SidebarResizeHandle, skipOffstage: false),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();

      expect(appCubit.state.membersSidebarWidth, K.membersSidebarMinWidth);
    });
  });
}
