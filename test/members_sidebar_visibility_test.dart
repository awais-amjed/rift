import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/logic/cubits/channel_presence/channel_presence_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/members_sidebar/members_sidebar.dart';

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
  Future<({bool success, List<ServerMember>? members, String? error})>
  listMembers() async =>
      (success: true, members: <ServerMember>[], error: null);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A roster that has already loaded and is empty — no realtime connection, so
/// the layout test doesn't need a server to talk to.
class _StubMembersCubit extends Cubit<ServerMembersState>
    implements ServerMembersCubit {
  _StubMembersCubit()
    : super(ServerMembersState(members: const <ServerMember>[]));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, AppCubit appCubit) async {
  await tester.pumpWidget(
    MaterialApp(
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
          child: const Row(
            children: [
              Expanded(child: SizedBox()),
              MembersSidebar(),
            ],
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
}
