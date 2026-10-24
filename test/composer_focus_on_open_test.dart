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

/// The composer writing to [conversation]; pumped again with another, it is
/// the same composer carried over, as when the open channel changes.
Future<void> _pumpComposer(WidgetTester tester, Object conversation) async {
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
              conversation: conversation,
              onSend: (_, _, _, _) async => false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _focused(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('opening a conversation puts the caret in the field', (
    tester,
  ) async {
    await _pumpComposer(tester, 'general');
    expect(_focused(tester), isTrue);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('another conversation takes the caret back, the same one not', (
    tester,
  ) async {
    await _pumpComposer(tester, 'general');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // A rebuild of the conversation already open leaves focus where it went.
    await _pumpComposer(tester, 'general');
    expect(_focused(tester), isFalse);

    await _pumpComposer(tester, 'random');
    expect(_focused(tester), isTrue);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets(
    'a phone does not throw its keyboard up on open',
    (tester) async {
      await _pumpComposer(tester, 'general');
      await _pumpComposer(tester, 'random');
      expect(_focused(tester), isFalse);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
