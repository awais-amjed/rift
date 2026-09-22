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
  StubMembersCubit() : super(ServerMembersState(loaded: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
