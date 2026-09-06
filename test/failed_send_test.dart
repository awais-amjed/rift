import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/chat_message_list.dart';

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

/// What a message that did not get out looks like.
///
/// Before the outbox it looked like nothing: the optimistic row was removed
/// and a toast said so, which meant a sentence typed on a bad connection was
/// gone by the time the connection came back.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final base = DateTime.utc(2026, 9, 4, 12);

  ChatMessage mine(
    String id, {
    String text = 'ok sounds good',
    bool pending = false,
    bool failed = false,
    int second = 0,
  }) => ChatMessage(
    id: id,
    authorId: 'me',
    authorName: 'Me',
    text: text,
    sentAt: base.add(Duration(seconds: second)),
    isMine: true,
    isPending: pending,
    sendFailed: failed,
  );

  Future<void> pump(
    WidgetTester tester,
    List<ChatMessage> messages, {
    void Function(String pendingId)? onRetry,
  }) => tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        // The row's message cover reads the sensitive-content setting.
        BlocProvider<AppCubit>(create: (_) => AppCubit()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ChatMessageList(messages: messages, onRetry: onRetry),
        ),
      ),
    ),
  );

  testWidgets('a failed send keeps its text on screen', (tester) async {
    await pump(tester, [
      mine('pending-0', pending: true, failed: true),
    ], onRetry: (_) {});

    expect(find.text('ok sounds good'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Sending…'), findsNothing);
  });

  testWidgets('one still in flight says it is sending, not that it failed', (
    tester,
  ) async {
    await pump(tester, [mine('pending-0', pending: true)]);
    expect(find.text('Sending…'), findsOneWidget);
    expect(find.text('Not sent'), findsNothing);
  });

  testWidgets('tapping the label asks for a retry, by pending id', (
    tester,
  ) async {
    final asked = <String>[];
    await pump(tester, [
      mine('pending-7', pending: true, failed: true),
    ], onRetry: asked.add);

    await tester.tap(find.text('Retry'));
    expect(asked, ['pending-7']);
  });

  testWidgets('a surface with no outbox offers nothing to press', (
    tester,
  ) async {
    // Still says it did not send — that part is the message reporting on
    // itself, and is true whether or not anybody can act on it.
    await pump(tester, [mine('pending-0', pending: true, failed: true)]);
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('it does not hide under the message before it', (tester) async {
    // Consecutive messages from one person collapse under a single header, and
    // "Not sent" lives in that header. Without the group key knowing about it,
    // the failed row would be drawn bare — no label, no way back.
    await pump(tester, [
      mine('1', text: 'first'),
      mine('pending-0', text: 'second', pending: true, failed: true, second: 2),
    ], onRetry: (_) {});

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
