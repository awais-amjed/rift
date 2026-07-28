import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/chat_composer.dart';

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

Future<void> _pumpComposer(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(onSend: (_, _) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  group('composer alignment', () {
    testWidgets('every control shares the row centre line', (tester) async {
      await _pumpComposer(tester);

      final field = tester.getRect(find.byType(EditableText));
      final attach = tester.getRect(find.byIcon(Icons.attach_file_rounded));
      final emoji = tester.getRect(
        find.byIcon(Icons.sentiment_satisfied_alt_rounded),
      );
      final mic = tester.getRect(find.byIcon(Icons.mic_none_rounded));
      final send = tester.getRect(find.byIcon(Icons.arrow_upward_rounded));

      for (final control in {
        'attach': attach,
        'emoji': emoji,
        'mic': mic,
        'send': send,
      }.entries) {
        expect(
          control.value.center.dy,
          moreOrLessEquals(field.center.dy, epsilon: 0.5),
          reason: '${control.key} is off the text centre line',
        );
      }
    });

    testWidgets('typing does not change the bar height', (tester) async {
      await _pumpComposer(tester);

      final before = tester.getRect(find.byType(ChatComposer)).height;
      await tester.enterText(find.byType(TextField), 'hello 😄');
      await tester.pump();
      final after = tester.getRect(find.byType(ChatComposer)).height;

      expect(after, before);
    });

    testWidgets('a second line grows the bar but keeps icons at the bottom', (
      tester,
    ) async {
      await _pumpComposer(tester);

      final oneLine = tester.getRect(find.byType(ChatComposer)).height;

      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pump();

      final twoLines = tester.getRect(find.byType(ChatComposer)).height;
      final field = tester.getRect(find.byType(EditableText));
      final send = tester.getRect(find.byIcon(Icons.arrow_upward_rounded));

      expect(twoLines, greaterThan(oneLine));
      // The bar grows upward and the buttons stay on the last line rather than
      // drifting to the middle of a tall field.
      expect(send.center.dy, greaterThan(field.center.dy));
      expect(send.bottom, lessThanOrEqualTo(field.bottom + 0.5));
    });
  });
}
