import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/friend.dart';
import 'package:rift/data/classes/friend_directory.dart';
import 'package:rift/data/enums/friendship_state.dart';
import 'package:rift/logic/cubits/central_dm/central_dm_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/empty_state.dart';
import 'package:rift/presentation/common/hint_card.dart';
import 'package:rift/presentation/screens/home/dms/widgets/friends/friend_row.dart';
import 'package:rift/presentation/screens/home/dms/widgets/friends/friends_list.dart';
import 'package:rift/presentation/screens/home/dms/widgets/friends/friends_tab_bar.dart';

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

class _StubCentralDmCubit extends Cubit<CentralDmState>
    implements CentralDmCubit {
  _StubCentralDmCubit(FriendDirectory graph)
    : super(CentralDmState(status: CentralDmStatus.ready, graph: graph));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What each friends tab shows with nothing in it.
///
/// The empty state used to be a [HintCard] — a bordered grey panel pinned
/// under the tabs, which read as a row that had failed to render rather than
/// as a list with nothing in it. These assert the replacement stays a
/// replacement: the card must not come back, and each tab must say its own
/// thing, because "nothing here" for three different reasons is three
/// different sentences.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> pump(
    WidgetTester tester,
    FriendsTab tab,
    FriendDirectory graph,
  ) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<CentralDmCubit>(
            create: (_) => _StubCentralDmCubit(graph),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: FriendsList(tab: tab)),
        ),
      ),
    );
  }

  const empty = FriendDirectory.empty();

  testWidgets('every tab has its own empty state, and none of them is a card', (
    tester,
  ) async {
    for (final (tab, title) in const [
      (FriendsTab.friends, 'No friends yet'),
      (FriendsTab.pending, 'Nothing pending'),
      (FriendsTab.blocked, 'Nobody blocked'),
    ]) {
      await pump(tester, tab, empty);

      expect(find.byType(EmptyState), findsOneWidget, reason: '$tab');
      expect(find.byType(HintCard), findsNothing, reason: '$tab');
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('a tab with rows in it shows rows and no empty state', (
    tester,
  ) async {
    final graph = FriendDirectory(
      friends: const [
        Friend(id: 'u1', handle: 'ana', state: FriendshipState.friends),
      ],
    );

    await pump(tester, FriendsTab.friends, graph);
    expect(find.byType(FriendRow), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    // The other two tabs are still empty, and read the graph independently —
    // a friend is not a pending request.
    await pump(tester, FriendsTab.pending, graph);
    expect(find.text('Nothing pending'), findsOneWidget);
  });

  testWidgets('half a pending tab is not an empty one', (tester) async {
    // Pending is the one tab with two halves. Only one of them being filled
    // still means there is something waiting, so the empty state must not
    // stand in for the missing half.
    final graph = FriendDirectory(
      outgoing: const [
        Friend(id: 'u3', handle: 'cy', state: FriendshipState.outgoing),
      ],
    );

    await pump(tester, FriendsTab.pending, graph);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.text('WAITING FOR THEM'), findsOneWidget);
  });
}
