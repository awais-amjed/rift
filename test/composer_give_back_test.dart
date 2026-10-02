import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
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

/// A composer whose sends wait on [answer], so a test can type in between the
/// press and the server's reply.
Future<List<String>> _pumpComposer(
  WidgetTester tester,
  Completer<bool> Function() answer,
) async {
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
              onSend: (text, _, _) {
                sent.add(text);
                return answer().future;
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

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
}

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  // F-4: a DM refused by a block or the new-DM limit used to take the words
  // with it.
  testWidgets('a refused message comes back to the field', (tester) async {
    final reply = Completer<bool>();
    final sent = await _pumpComposer(tester, () => reply);

    await _send(tester, 'hello there');
    expect(sent, ['hello there']);
    expect(_field(tester), isEmpty);

    reply.complete(true);
    await tester.pump();
    expect(_field(tester), 'hello there');
  });

  testWidgets('a message that went stays gone', (tester) async {
    final reply = Completer<bool>();
    await _pumpComposer(tester, () => reply);

    await _send(tester, 'hello there');
    reply.complete(false);
    await tester.pump();
    expect(_field(tester), isEmpty);
  });

  testWidgets('words typed since the send are not overwritten', (tester) async {
    final reply = Completer<bool>();
    await _pumpComposer(tester, () => reply);

    await _send(tester, 'hello there');
    await tester.enterText(find.byType(EditableText), 'something new');
    await tester.pump();

    reply.complete(true);
    await tester.pump();
    expect(_field(tester), 'something new');
  });
}
