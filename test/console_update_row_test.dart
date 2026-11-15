import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/console_update.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/repositories/server_session.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/server_scope.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/console_update_row.dart';

import 'support/memory_storage.dart';

const _update = ConsoleUpdate(
  version: '1.7.0',
  url: 'https://example.test/1.7.0',
  notes: 'Faster backups.',
);

Server _server({required bool admin, ConsoleUpdate? update = _update}) =>
    Server(
      id: 's1',
      name: 'Server1',
      supabaseUrl: 'http://localhost',
      token: 't',
      user: ServerUser(
        id: 'me',
        username: 'me',
        displayName: 'Me',
        permissions: UserPermissions(isServerAdmin: admin),
      ),
      consoleUpdate: update,
    );

Future<void> _pump(WidgetTester tester, Server server) => tester.pumpWidget(
  BlocProvider(
    create: (_) => ThemeCubit(),
    child: MaterialApp(
      home: Scaffold(
        body: ServerScope(
          server: ServerSession(SessionRepository(), 's1'),
          child: SizedBox(width: 260, child: ConsoleUpdateRow(server: server)),
        ),
      ),
    ),
  ),
);

/// An admin is told under the server's name when its console has a newer
/// release; pressing it says which and how to update. Nobody else is told.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('an admin sees the release', (tester) async {
    await _pump(tester, _server(admin: true));
    expect(find.text('Console 1.7.0 available'), findsOneWidget);
  });

  testWidgets('nothing without an update, or for anybody else', (tester) async {
    await _pump(tester, _server(admin: true, update: null));
    expect(find.textContaining('Console'), findsNothing);
    await _pump(tester, _server(admin: false));
    expect(find.textContaining('Console'), findsNothing);
  });

  testWidgets('pressing it shows the notes and the command', (tester) async {
    await _pump(tester, _server(admin: true));
    await tester.tap(find.text('Console 1.7.0 available'));
    await tester.pumpAndSettle();
    expect(find.text('Console 1.7.0 is out'), findsOneWidget);
    expect(find.textContaining('Faster backups.'), findsOneWidget);
    expect(find.text('docker compose exec console update'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
