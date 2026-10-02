import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_switch.dart';

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

/// F-18: Tab went straight past every switch in the app — the Private
/// channel switch in "Create channel" could only be reached with a mouse.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<List<bool>> host(WidgetTester tester, {bool enabled = true}) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  final value = changes.isNotEmpty && changes.last;
                  return AppSwitch(
                    value: value,
                    onChanged: enabled
                        ? (v) => setState(() => changes.add(v))
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('Tab reaches the switch and Space flips it', (tester) async {
    final changes = await host(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(changes, [true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(changes, [true, false]);
  });

  testWidgets('a locked switch is skipped and does not flip', (tester) async {
    final changes = await host(tester, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(changes, isEmpty);
  });
}
