import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/repositories/server_session.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/server_scope.dart';
import 'package:rift/presentation/screens/home/servers/add_server/publish_new_server_modal.dart';

/// The add-server dialog is opened over whichever server is on screen, and
/// carries that server's scope. Joining moves the selection to the new
/// server, but not the scope: the last step, read from it, said "Rift Test
/// is invite-only" over Lighthouse's questions, and its Publish would have
/// listed Rift Test.

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

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubBackupCubit extends Cubit<SupabaseBackupState>
    implements SupabaseBackupCubit {
  _StubBackupCubit() : super(const SupabaseBackupState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Server _server(String id, String name) =>
    Server(id: id, name: name, supabaseUrl: 'https://$id.invalid', token: 't');

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('is about the server just joined, not the one it opened over', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider<ServerCubit>(
            create: (_) => _StubServerCubit(
              ServerState(
                servers: [
                  _server('rift-test', 'Rift Test'),
                  _server('lighthouse', 'Lighthouse'),
                ],
                selectedServerId: 'lighthouse',
              ),
            ),
          ),
          BlocProvider<SupabaseBackupCubit>(create: (_) => _StubBackupCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ServerScope(
              server: ServerSession(SessionRepository(), 'rift-test'),
              child: PublishNewServerModal(
                onDone: () {},
                serverId: 'lighthouse',
                joined: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Lighthouse is invite-only'), findsOneWidget);
    expect(find.textContaining('Rift Test'), findsNothing);
  });
}
