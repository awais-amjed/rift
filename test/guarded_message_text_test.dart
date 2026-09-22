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
        body: GuardedMessageText(
          messageId: id,
          text: text,
          builder: (shown, reveal) => Text.rich(
            TextSpan(text: shown, children: [?reveal]),
          ),
        ),
      ),
    ),
  );

  testWidgets('a clean message is shown as is', (tester) async {
    await tester.pumpWidget(guarded('hello there'));
    expect(find.text('hello there'), findsOneWidget);
  });

  testWidgets('blur mode covers only the word, until Show is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(guarded('well fuck that'));
    expect(find.text('well •••• that  Show'), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('Show'));
    await tester.pump();
    expect(find.text('well fuck that'), findsOneWidget);
  });

  testWidgets('every flagged word is covered', (tester) async {
    await tester.pumpWidget(guarded('fuck this, fuuuck that'));
    expect(find.text('•••• this, •••••• that  Show'), findsOneWidget);
  });

  testWidgets('hide mode covers the word with no way through', (
    tester,
  ) async {
    app.setSensitiveContentMode(SensitiveContentMode.hide);
    await tester.pumpWidget(guarded('well fuck'));
    expect(find.text('well ••••'), findsOneWidget);
  });

  testWidgets('off shows everything', (tester) async {
    app.setSensitiveContentMode(SensitiveContentMode.off);
    await tester.pumpWidget(guarded('well fuck'));
    expect(find.text('well fuck'), findsOneWidget);
  });
}
