import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/poll.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/live_bar/live_bar.dart';
import 'package:rift/presentation/common/chat/polls/message_poll_card.dart';
import 'package:rift/presentation/common/chat/polls/poll_option_row.dart';
import 'package:rift/presentation/theme/app_theme.dart';

import 'support/memory_storage.dart';

/// The bar above a channel's message box: folded to one line, opened on a
/// tap, folded again only when the reader folds it, and gone when nothing in
/// the channel is live.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  final start = DateTime.utc(2026, 10, 27, 12);

  ChatMessage poll(String id, String question, {Duration? closesIn}) =>
      ChatMessage(
        id: id,
        authorId: 'a',
        authorName: 'A',
        text: '',
        sentAt: start,
        isMine: false,
        poll: Poll(
          question: question,
          options: const ['Mirage', 'Inferno'],
          multiple: false,
          closesAt: start.add(closesIn ?? const Duration(hours: 2)),
        ),
      );

  Future<void> pump(
    WidgetTester tester, {
    required List<ChatMessage> live,
    Map<String, PollTally> tallies = const {},
    void Function(String, int)? onVote,
    DateTime Function()? now,
    double maxHeight = 400,
  }) {
    final themeCubit = ThemeCubit();
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        child: MaterialApp(
          theme: AppTheme.fromPalette(
            themeCubit.state.palette,
            Brightness.dark,
          ),
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LiveBar(
                  live: live,
                  tallies: tallies,
                  onVote: onVote ?? (_, _) {},
                  onClosePoll: null,
                  now: now ?? () => start,
                  maxHeight: maxHeight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final three = [
    poll('30', 'Which map tonight?'),
    poll('20', 'Friday or Saturday for the LAN?'),
    poll('10', 'Snacks?'),
  ];

  testWidgets('nothing open draws nothing', (tester) async {
    await pump(
      tester,
      live: [poll('1', 'Over?', closesIn: const Duration(hours: -1))],
    );
    expect(find.byType(LiveBar), findsOneWidget);
    expect(find.text('Over?'), findsNothing);
    expect(tester.getSize(find.byType(LiveBar)).height, 0);
  });

  testWidgets('folded shows the newest question and +2 more', (tester) async {
    await pump(tester, live: three);
    expect(find.text('Which map tonight?'), findsOneWidget);
    expect(find.text('+2 more'), findsOneWidget);
    expect(find.text('Snacks?'), findsNothing);
    expect(find.byType(MessagePollCard), findsNothing);
  });

  testWidgets('a tap opens every open poll, newest first', (tester) async {
    await pump(tester, live: three);
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    final cards = tester
        .widgetList<MessagePollCard>(find.byType(MessagePollCard))
        .map((c) => c.poll.question)
        .toList();
    expect(cards, [
      'Which map tonight?',
      'Friday or Saturday for the LAN?',
      'Snacks?',
    ]);
    expect(find.text('3 open polls'), findsOneWidget);
  });

  testWidgets('Escape folds it', (tester) async {
    await pump(tester, live: three);
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    expect(find.byType(MessagePollCard), findsNWidgets(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MessagePollCard), findsNothing);
  });

  testWidgets('a vote does not fold it', (tester) async {
    final votes = <(String, int)>[];
    await pump(tester, live: three, onVote: (id, o) => votes.add((id, o)));
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PollOptionRow).first);
    await tester.pumpAndSettle();
    expect(votes, [('30', 0)]);
    expect(find.byType(MessagePollCard), findsNWidgets(3));
  });

  testWidgets('a tap on the open line folds it', (tester) async {
    await pump(tester, live: three);
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 open polls'));
    await tester.pumpAndSettle();
    expect(find.byType(MessagePollCard), findsNothing);
  });

  testWidgets('a poll leaves the bar when it closes', (tester) async {
    var clock = start;
    await pump(
      tester,
      live: [poll('1', 'Quick one?', closesIn: const Duration(seconds: 1))],
      now: () => clock,
    );
    expect(find.text('Quick one?'), findsOneWidget);
    clock = start.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Quick one?'), findsNothing);
  });

  testWidgets('opened polls stay within maxHeight', (tester) async {
    await pump(
      tester,
      live: [for (var i = 9; i > 0; i--) poll('$i', 'Poll $i?')],
      maxHeight: 200,
    );
    await tester.tap(find.text('Poll 9?'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scroller = find.descendant(
      of: find.byType(LiveBar),
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getSize(scroller).height, lessThanOrEqualTo(200));
  });
}
