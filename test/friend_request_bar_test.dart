import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/central_dm/central_dm_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/dms/widgets/friends/friend_request_bar.dart';
import 'package:rift/presentation/screens/home/dms/widgets/friends/not_friends_note.dart';
import 'package:rift/presentation/screens/home/dms/widgets/friends/pending_request_note.dart';

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
  _StubCentralDmCubit() : super(const CentralDmState());

  final List<String> accepted = [];
  final List<String> declined = [];
  final List<String> withdrawn = [];
  final List<String> added = [];
  final List<String> unblocked = [];

  @override
  Future<bool> acceptRequest(String peerId) async {
    accepted.add(peerId);
    return true;
  }

  @override
  Future<bool> declineRequest(String peerId) async {
    declined.add(peerId);
    return true;
  }

  @override
  Future<bool> removeFriend(String peerId) async {
    withdrawn.add(peerId);
    return true;
  }

  @override
  Future<bool> addFriend(String peerId) async {
    added.add(peerId);
    return true;
  }

  @override
  Future<bool> unblockPeer(String peerId) async {
    unblocked.add(peerId);
    return true;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What stands where the composer would be, for somebody who is not a friend.
/// The point of all three widgets is that they are *not* a disabled composer —
/// a greyed field reads as breakage, and people retype into it.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<_StubCentralDmCubit> pump(WidgetTester tester, Widget child) async {
    final cubit = _StubCentralDmCubit();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<CentralDmCubit>.value(value: cubit),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    return cubit;
  }

  testWidgets('a request offers the three answers and says why it is quiet', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      const FriendRequestBar(peerId: 'u2', peerHandle: 'bo'),
    );

    expect(find.text('@bo wants to be friends'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    // The one place with room to say that the silence is enforced rather than
    // a door the reader is holding shut by hand.
    expect(
      find.textContaining('cannot send you anything until you accept'),
      findsOneWidget,
    );

    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(cubit.accepted, ['u2']);

    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(cubit.declined, ['u2']);
  });

  testWidgets('a request of your own says it is waiting, and can be taken back', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      const PendingRequestNote(peerId: 'u3', peerHandle: 'cy'),
    );

    expect(find.textContaining('Waiting for @cy'), findsOneWidget);
    expect(find.textContaining('once they do'), findsOneWidget);

    await tester.tap(find.text('Withdraw'));
    await tester.pump();
    expect(cubit.withdrawn, ['u3']);
  });

  testWidgets('an ex-friend gets a readable conversation and a way back', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      const NotFriendsNote(peerId: 'u5', peerHandle: 'dex'),
    );

    expect(find.textContaining('You and @dex are not friends'), findsOneWidget);

    await tester.tap(find.text('Add friend'));
    await tester.pump();
    expect(cubit.added, ['u5']);
  });

  testWidgets('somebody you blocked is told so, and offered the undo', (
    tester,
  ) async {
    final cubit = await pump(
      tester,
      const NotFriendsNote(peerId: 'u6', peerHandle: 'eve', isBlocked: true),
    );

    // Named plainly, because this is the reader's own decision — the silence
    // only has to be kept in the other direction.
    expect(find.textContaining('You have @eve blocked'), findsOneWidget);
    expect(find.text('Add friend'), findsNothing);

    await tester.tap(find.text('Unblock'));
    await tester.pump();
    expect(cubit.unblocked, ['u6']);
  });
}
