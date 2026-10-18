import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/repositories/server_session.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/server_scope.dart';
import 'package:rift/presentation/screens/home/profile/user_dock/user_dock.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/sidebar_header.dart';

import 'shell_scope_harness.dart';

/// Joining a server adds it and selects it in one change. The sidebar's
/// header and the dock each filtered the server's state with a `buildWhen`
/// that held the id of the build before, so neither let that change through,
/// and redrawn for the new scope they looked the new server up in the list
/// from before it existed: "No server selected" over its channels, and
/// "Guest" in the dock, until something else about it changed.

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

class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit(super.state);

  void land(ServerState next) => emit(next);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit() : super(const LiveKitState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Server _server(String id, String name, String me) => Server(
  id: id,
  name: name,
  supabaseUrl: 'https://$id.invalid',
  token: 't',
  user: ServerUser(
    id: 'me@$id',
    username: me,
    displayName: me,
    permissions: const UserPermissions(),
  ),
);

/// The selected server's scope, as `SelectedServerScope` provides it.
class _SelectedScope extends StatelessWidget {
  final SessionRepository session;
  final Widget child;

  const _SelectedScope({required this.session, required this.child});

  @override
  Widget build(BuildContext context) {
    final id = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServerId,
    );
    if (id == null) return child;
    return ServerScope(server: ServerSession(session, id), child: child);
  }
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('a server joined and selected at once is the one drawn', (
    tester,
  ) async {
    final riftTest = _server('rift-test', 'Rift Test', 'Switcher');
    final servers = _StubServerCubit(
      ServerState(servers: [riftTest], selectedServerId: 'rift-test'),
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider(create: (_) => AppCubit()),
          BlocProvider<ServerCubit>.value(value: servers),
          BlocProvider<LiveKitCubit>(create: (_) => _StubLiveKitCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 288,
              child: withShellScope(
                _SelectedScope(
                  session: SessionRepository(),
                  child: const Column(
                    children: [SidebarHeader(), Spacer(), UserDock()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Rift Test'), findsOneWidget);

    servers.land(
      ServerState(
        servers: [riftTest, _server('lighthouse', 'Lighthouse', 'Keeper')],
        selectedServerId: 'lighthouse',
      ),
    );
    // The change reaches the widgets a microtask later, and the frame after.
    await tester.pump();
    await tester.pump();

    expect(find.text('Lighthouse'), findsOneWidget);
    expect(find.text('No server selected'), findsNothing);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text('Guest'), findsNothing);
  });
}
