import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/checkbox_row.dart';
import 'package:rift/presentation/theme/app_text.dart';

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

Future<void> _pumpRow(WidgetTester tester, String label, double width) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<ThemeCubit>(
          create: (_) => ThemeCubit(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CheckboxRow(label: label, value: false, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final line = AppText.body.fontSize! * AppText.body.height!;

  // "Choose the sound this time" sat a few pixels above its box: the label
  // was placed by a guessed padding.
  testWidgets('a one-line label shares the box\'s centre line', (tester) async {
    await _pumpRow(tester, 'Choose the sound this time', 600);

    final box = tester.getRect(find.byType(Checkbox));
    final text = tester.getRect(find.byType(Text));
    expect(text.center.dy, moreOrLessEquals(box.center.dy, epsilon: 0.5));
  });

  testWidgets('a label that wraps keeps its first line on the box', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      'I have saved my recovery key somewhere safe, and I know where it is.',
      200,
    );

    final box = tester.getRect(find.byType(Checkbox));
    final text = tester.getRect(find.byType(Text));
    expect(text.height, greaterThan(line * 1.5));
    expect(text.top + line / 2, moreOrLessEquals(box.center.dy, epsilon: 0.5));
  });
}
