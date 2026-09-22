import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/enums/sensitive_content_mode.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/text_safety.dart';
import 'package:rift/presentation/common/chat/message_row/guarded_message_text.dart';

class _Storage extends Storage {
  final Map<String, dynamic> _m = {};
  @override
  dynamic read(String key) => _m[key];
  @override
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
  @override
  Future<void> clear() async => _m.clear();
  @override
  Future<void> close() async {}
}

void main() {
  late AppCubit app;

  setUpAll(() {
    HydratedBloc.storage = _Storage();
    TextSafety.instance.install([
      {'id': 'fuck', 'match': 'fu*ck', 'severity': 3},
    ]);
  });

  setUp(() {
    GuardedMessageText.resetReveals();
    app = AppCubit();
  });

  Widget guarded(String text, {String id = 'm1'}) => MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: app),
        BlocProvider(create: (_) => ThemeCubit()),
      ],
      child: Scaffold(
        body: GuardedMessageText(messageId: id, text: text, child: Text(text)),
      ),
    ),
  );

  testWidgets('a clean message is shown as is', (tester) async {
    await tester.pumpWidget(guarded('hello there'));
    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('Sensitive message'), findsNothing);
  });

  testWidgets('blur mode covers a flagged message until tapped', (
    tester,
  ) async {
    await tester.pumpWidget(guarded('well fuck'));
    expect(find.text('well fuck'), findsNothing);
    expect(find.text('Sensitive message'), findsOneWidget);

    await tester.tap(find.text('Sensitive message'));
    await tester.pump();
    expect(find.text('well fuck'), findsOneWidget);
  });

  testWidgets('hide mode has no way through', (tester) async {
    app.setSensitiveContentMode(SensitiveContentMode.hide);
    await tester.pumpWidget(guarded('well fuck'));
    await tester.tap(find.text('Sensitive message'));
    await tester.pump();
    expect(find.text('well fuck'), findsNothing);
    expect(find.textContaining('Hidden by your settings'), findsOneWidget);
  });

  testWidgets('off shows everything', (tester) async {
    app.setSensitiveContentMode(SensitiveContentMode.off);
    await tester.pumpWidget(guarded('well fuck'));
    expect(find.text('well fuck'), findsOneWidget);
  });
}
