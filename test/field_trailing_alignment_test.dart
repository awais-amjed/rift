import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/channels/webhooks/widgets/webhook_create_row.dart';

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

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  // The webhook's Create button sat two pixels off its field: it was lined up
  // with the bottom of the character counter by a guessed padding.
  testWidgets('a field\'s trailing button shares the box\'s centre line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<ThemeCubit>(
            create: (_) => ThemeCubit(),
            // In a column, as on the page: unbounded height, so the field
            // is as tall as its label, box and counter and no taller.
            child: Column(
              children: [
                WebhookCreateRow(
                  controller: TextEditingController(),
                  isBusy: false,
                  onChanged: (_) {},
                  onCreate: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final text = tester.getRect(find.byType(EditableText));
    final button = tester.getRect(find.text('Create'));
    expect(button.center.dy, moreOrLessEquals(text.center.dy, epsilon: 0.5));
  });
}
