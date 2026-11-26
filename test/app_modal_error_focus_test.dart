import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_modal.dart';

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

/// A form whose error clears on the first keystroke, as the app's dialogs do.
class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error = 'Something was wrong';

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppModal(
    title: 'Edit',
    error: error,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('first'),
          controller: first,
          autofocus: true,
          onChanged: (_) => setState(() => error = null),
        ),
        TextField(
          key: const ValueKey('second'),
          controller: second,
          onChanged: (_) => setState(() => error = null),
        ),
      ],
    ),
  );
}

/// The error banner coming or going must not rebuild the form under it. It
/// did: the form sat in a column only while there was an error, so clearing
/// it on the first keystroke made every field anew, and the autofocused first
/// field took the focus back. In the voice region dialog the first letter of
/// a new address went into the address and the rest into the region's name
/// (found live Nov 27).
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('typing that clears the error stays in its field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: const MaterialApp(home: Scaffold(body: _Form())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('second')));
    await tester.pump();
    final state = tester.state<_FormState>(find.byType(_Form));
    expect(state.error, isNotNull);

    // One keystroke at a time, as a person types: the first clears the error.
    for (final text in ['w', 'ws', 'ws:']) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      await tester.pump();
    }

    expect(state.error, isNull);
    expect(state.second.text, 'ws:');
    expect(state.first.text, isEmpty);
  });
}
