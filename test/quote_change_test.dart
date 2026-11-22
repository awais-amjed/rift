import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/quote_lookup.dart';
import 'package:rift/presentation/common/chat/chat_message_list.dart';

import 'support/stub_members_cubit.dart';

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

/// A reply on the page can quote a message from further back, fetched once
/// for the quote. When that message is edited or deleted the conversation
/// says so ([OffPageChanges]), and the quote is fetched again, rather than
/// keeping the old words until the conversation is opened again.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final base = DateTime.utc(2026, 1, 1, 12);

  ChatMessage original(String text) => ChatMessage(
    id: '1',
    authorId: 'ana',
    authorName: 'ana',
    text: text,
    sentAt: base,
    isMine: false,
  );

  final reply = ChatMessage(
    id: '600',
    authorId: 'bo',
    authorName: 'bo',
    text: 'agreed',
    sentAt: base.add(const Duration(days: 1)),
    isMine: false,
    replyToId: '1',
  );

  late List<QuotedMessage> answers;
  late int asked;
  late StreamController<String> changes;

  setUp(() {
    asked = 0;
    changes = StreamController.broadcast();
  });

  tearDown(() => changes.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
          BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageList(
              messages: [reply],
              onLookUpOriginal: (_) async =>
                  answers[(asked++).clamp(0, answers.length - 1)],
              quoteChanges: changes.stream,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an edit to the quoted message reaches the quote', (
    tester,
  ) async {
    answers = [
      QuotedMessage.found(original('old words')),
      QuotedMessage.found(original('new words')),
    ];
    await pump(tester);
    expect(find.textContaining('old words'), findsOneWidget);

    changes.add('1');
    await tester.pumpAndSettle();
    expect(asked, 2);
    expect(find.textContaining('new words'), findsOneWidget);
    expect(find.textContaining('old words'), findsNothing);
  });

  testWidgets('a deletion of it does too', (tester) async {
    answers = [
      QuotedMessage.found(original('old words')),
      const QuotedMessage.deleted(),
    ];
    await pump(tester);
    changes.add('1');
    await tester.pumpAndSettle();
    expect(find.textContaining('old words'), findsNothing);
  });

  testWidgets('a lookup that fails keeps the quote it had', (tester) async {
    answers = [
      QuotedMessage.found(original('old words')),
      const QuotedMessage.unknown(),
    ];
    await pump(tester);
    changes.add('1');
    await tester.pumpAndSettle();
    expect(asked, 2);
    expect(find.textContaining('old words'), findsOneWidget);
  });

  testWidgets('a change to a message nothing quotes asks nothing', (
    tester,
  ) async {
    answers = [QuotedMessage.found(original('old words'))];
    await pump(tester);
    changes.add('77');
    await tester.pumpAndSettle();
    expect(asked, 1);
  });
}
