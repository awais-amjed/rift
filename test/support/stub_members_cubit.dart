import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';

/// A roster that has loaded and holds nobody — for widget tests that draw a
/// member's avatar, which reads the live picture from here and falls back to
/// the one it was given. No realtime connection, no server.
///
/// ```dart
/// BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
/// ```
class StubMembersCubit extends Cubit<ServerMembersState>
    implements ServerMembersCubit {
  StubMembersCubit([ServerMembersState? state])
    : super(state ?? ServerMembersState(loaded: true));

  /// Asked by anything that wants a member's row and roles read in; the
  /// state handed in already holds whatever the test wants known.
  @override
  Future<void> resolve(Iterable<String> userIds) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
