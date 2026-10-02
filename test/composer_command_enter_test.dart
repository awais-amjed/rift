import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/bot_manifest.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/composer/chat_composer.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
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

const _music = ServerMember(
  id: 'id-musicbot',
  username: 'musicbot',
  displayName: 'musicbot',
  permissions: UserPermissions(),
  isBot: true,
  manifest: BotManifest(
    commands: [
      BotCommandSpec(name: 'play', usage: '<song>'),
      BotCommandSpec(name: 'stop'),
    ],
  ),
);

Future<List<String>> _pumpComposer(WidgetTester tester) async {
  final sent = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
            BlocProvider<AppCubit>(create: (_) => AppCubit()),
          ],
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              bots: const [_music],
              onSend: (text, _, _) {
                sent.add(text);
                return Future.value(false);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return sent;
}

String _field(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

Future<void> _typeThenEnter(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

/// F-24: with the `/` menu showing, Enter always took the suggestion first, so
/// a command typed out in full needed a second Enter to go.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('a whole command with no arguments sends on Enter', (
    tester,
  ) async {
    final sent = await _pumpComposer(tester);
    await _typeThenEnter(tester, '/stop');
    expect(sent, ['/stop']);
  });

  testWidgets('a fragment completes and waits', (tester) async {
    final sent = await _pumpComposer(tester);
    await _typeThenEnter(tester, '/st');
    expect(sent, isEmpty);
    expect(_field(tester), '/stop ');
  });

  testWidgets('a command that wants arguments completes and waits', (
    tester,
  ) async {
    final sent = await _pumpComposer(tester);
    await _typeThenEnter(tester, '/play');
    expect(sent, isEmpty);
    expect(_field(tester), '/play ');
  });

  testWidgets('Tab still only completes', (tester) async {
    final sent = await _pumpComposer(tester);
    await tester.enterText(find.byType(EditableText), '/stop');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(sent, isEmpty);
    expect(_field(tester), '/stop ');
  });
}
