import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/server_nav_column.dart';

import 'shell_scope_harness.dart';

/// With no server at all, the sidebar drew a server's column anyway: a
/// "Server DMs" row, and the empty channel list saying "An admin has to
/// create the first one" about a server that did not exist.

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
  _StubServerCubit() : super(const ServerState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('with no server, the sidebar offers to add one', (tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider(create: (_) => AppCubit()),
          BlocProvider<ServerCubit>(create: (_) => _StubServerCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 288,
              child: withShellScope(const ServerNavColumn()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No server yet'), findsOneWidget);
    expect(find.text('Add a server'), findsOneWidget);
    expect(find.text('Server DMs'), findsNothing);
    expect(find.text('No channels yet'), findsNothing);
  });
}
