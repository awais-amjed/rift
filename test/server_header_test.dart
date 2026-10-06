import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/server_header.dart';

import 'shell_scope_harness.dart';

/// In-memory stand-in so the hydrated cubits can be built in tests.
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

Server _server() => Server(
  id: 'srv-1',
  name: 'Rift HQ',
  supabaseUrl: 'https://hq.example.co',
  token: 't',
);

Future<int Function()> _pumpHeader(WidgetTester tester) async {
  var opened = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider(create: (_) => AppCubit()),
        ],
        child: Scaffold(
          body: SizedBox(
            width: 288,
            child: withShellScope(
              ServerHeader(server: _server(), onInvite: () => opened++),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return () => opened;
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('the server header', () {
    testWidgets('does not invite when the name is tapped', (tester) async {
      final opened = await _pumpHeader(tester);

      await tester.tap(find.text('Rift HQ'));
      await tester.pump();

      // The identity is a label. Opening a dialog from it gives no warning
      // of what the tap will do.
      expect(opened(), 0);
    });

    testWidgets('does not invite when the E2E claim is tapped', (tester) async {
      final opened = await _pumpHeader(tester);

      await tester.tap(find.text('Encrypted'));
      await tester.pump();

      expect(opened(), 0);
    });

    testWidgets('invites from its button', (tester) async {
      final opened = await _pumpHeader(tester);

      await tester.tap(find.byIcon(Icons.person_add_outlined));
      await tester.pump();

      expect(opened(), 1);
    });

    testWidgets('the hide button stays its own control', (tester) async {
      final opened = await _pumpHeader(tester);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pump();

      // Hiding the sidebar must not also open the invite dialog.
      expect(opened(), 0);
      // And it only ever points one way: there is no pinned/unpinned mode for
      // it to describe any more, so it never becomes a pin.
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    });

    testWidgets('has no settings gear: settings is on the rail menu', (
      tester,
    ) async {
      await _pumpHeader(tester);

      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });
  });

  testWidgets('somebody who cannot invite gets no invite button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit()),
            BlocProvider(create: (_) => AppCubit()),
          ],
          child: Scaffold(
            body: SizedBox(
              width: 288,
              child: withShellScope(ServerHeader(server: _server())),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.person_add_outlined), findsNothing);
  });
}
