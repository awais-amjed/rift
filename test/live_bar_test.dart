import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/panel_block.dart';
import 'package:rift/data/classes/poll.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/live_bar/live_bar.dart';
import 'package:rift/presentation/common/chat/live_bar/live_bar_escape.dart';
import 'package:rift/presentation/common/chat/live_bar/widgets/live_panel_line.dart';
import 'package:rift/presentation/common/chat/live_bar/widgets/live_polls_line.dart';
import 'package:rift/presentation/common/chat/panel/panel_view.dart';
import 'package:rift/presentation/common/chat/polls/message_poll_card.dart';
import 'package:rift/presentation/common/chat/polls/poll_option_row.dart';
import 'package:rift/presentation/theme/app_theme.dart';

import 'support/memory_storage.dart';

/// The bar above a channel's message box: folded to one line, opened on a
/// tap, folded again only when the reader folds it, and gone when nothing in
/// the channel is live.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  // The real time: a poll card asks the clock itself whether its poll is
  // over, so a fixed date made every poll here closed once it had passed.
  final start = DateTime.now().toUtc();

  // One function across pumps, as the chat hands the cubit's own: a closure
  // made fresh each pump would be a new callback every time.
  void noVote(String _, int _) {}

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
    List<ChatMessage> panels = const [],
    void Function(String, String, String?)? onPanelAction,
    Map<String, PollTally> tallies = const {},
    void Function(String, int)? onVote,
    DateTime Function()? now,
    double maxHeight = 400,
    Widget? below,
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
            body: LiveBarEscape(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LiveBar(
                    live: live,
                    panels: panels,
                    onPanelAction: onPanelAction ?? (_, _, _) {},
                    tallies: tallies,
                    onVote: onVote ?? noVote,
                    onClosePoll: null,
                    now: now ?? () => start,
                    maxHeight: maxHeight,
                  ),
                  ?below,
                ],
              ),
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

  testWidgets('Escape goes first to a focused field that takes it', (
    tester,
  ) async {
    // A message being edited: Escape cancels the edit, and only an Escape
    // with nothing focused then folds the bar.
    final field = FocusNode();
    addTearDown(field.dispose);
    var cancels = 0;
    await pump(
      tester,
      live: three,
      below: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            cancels++;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(focusNode: field),
      ),
    );
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    field.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(find.byType(MessagePollCard), findsNWidgets(3));

    field.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(find.byType(MessagePollCard), findsNothing);
  });

  testWidgets('Escape from the message box folds it', (tester) async {
    // A field with no Escape of its own: the key comes through the chat.
    final field = FocusNode();
    addTearDown(field.dispose);
    await pump(
      tester,
      live: three,
      below: TextField(focusNode: field),
    );
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    field.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MessagePollCard), findsNothing);
  });

  testWidgets('Escape in a dialog above closes the dialog, not the bar', (
    tester,
  ) async {
    await pump(tester, live: three);
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(LiveBar)),
        builder: (_) => const AlertDialog(content: Text('A dialog')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('A dialog'), findsNothing);
    expect(find.byType(MessagePollCard), findsNWidgets(3));
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

  // ── The player ──────────────────────────────────────────

  ChatMessage player({
    String id = 'p1',
    String song = 'Windowlicker',
    double progress = 0.25,
  }) => ChatMessage(
    id: id,
    authorId: 'dj',
    authorName: 'DJ Riff',
    text: '',
    sentAt: start,
    isMine: false,
    panel: Panel.tryParse({
      'v': 1,
      'live': true,
      'blocks': [
        {'type': 'heading', 'text': 'Now playing'},
        {
          'type': 'fields',
          'items': [
            {'label': 'Song', 'value': song},
            {'label': 'Artist', 'value': 'Aphex Twin'},
          ],
        },
        {'type': 'progress', 'value': progress, 'text': '0:50 / 3:20'},
        {
          'type': 'actions',
          'items': [
            {'label': 'Pause', 'action': 'pause'},
            {'label': 'Skip', 'action': 'skip'},
            {'label': 'Stop', 'action': 'stop', 'style': 'danger'},
          ],
        },
      ],
    }),
  );

  testWidgets('the player line sits above the polls line', (tester) async {
    await pump(tester, live: three, panels: [player()]);
    expect(
      tester.getTopLeft(find.text('Windowlicker')).dy,
      lessThan(tester.getTopLeft(find.text('Which map tonight?')).dy),
    );
    expect(find.text('Aphex Twin · DJ Riff'), findsOneWidget);
  });

  testWidgets('a player alone draws the bar', (tester) async {
    await pump(tester, live: const [], panels: [player()]);
    expect(find.text('Windowlicker'), findsOneWidget);
  });

  testWidgets('opening the player folds the polls', (tester) async {
    await pump(tester, live: three, panels: [player()]);
    await tester.tap(find.text('Which map tonight?'));
    await tester.pumpAndSettle();
    expect(find.byType(MessagePollCard), findsNWidgets(3));
    await tester.tap(find.text('Windowlicker'));
    await tester.pumpAndSettle();
    expect(find.byType(MessagePollCard), findsNothing);
    expect(find.byType(PanelView), findsOneWidget);
    // Stop is in the opened panel, not on the folded line.
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('an opened player keeps its buttons out of the scroll', (
    tester,
  ) async {
    await pump(tester, live: const [], panels: [player()], maxHeight: 120);
    await tester.tap(find.text('Windowlicker'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scroller = find.descendant(
      of: find.byType(LiveBar),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      find.descendant(of: scroller, matching: find.text('Stop')),
      findsNothing,
    );
    expect(find.text('Stop'), findsOneWidget);
    // In sight: below the scroller, inside the bar.
    final bar = tester.getRect(find.byType(LiveBar));
    final stop = tester.getRect(find.text('Stop'));
    expect(stop.top, greaterThanOrEqualTo(tester.getRect(scroller).bottom));
    expect(bar.contains(stop.center), isTrue);
    // The top line's own buttons go while the full row is open.
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('Pause on the folded line presses the panel\'s action', (
    tester,
  ) async {
    final presses = <(String, String, String?)>[];
    await pump(
      tester,
      live: const [],
      panels: [player()],
      onPanelAction: (id, action, value) => presses.add((id, action, value)),
    );
    expect(find.text('Stop'), findsNothing);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(presses, [('p1', 'pause', null)]);
    expect(find.byType(PanelView), findsNothing);
  });

  testWidgets('the folded player line fits at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      live: three,
      panels: [
        player(
          song:
              'A song with a very long title that goes on and on, '
              'remastered, live at somewhere (deluxe edition)',
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('a redraw rebuilds the player line only', (tester) async {
    final polls = [...three];
    await pump(tester, live: [player(), ...polls], panels: [player()]);
    var pollLines = 0;
    var playerLines = 0;
    widgets.debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is LivePollsLine) pollLines++;
      if (element.widget is LivePanelLine) playerLines++;
    };
    try {
      final redrawn = player(progress: 0.5);
      await pump(tester, live: [redrawn, ...polls], panels: [redrawn]);
    } finally {
      widgets.debugOnRebuildDirtyWidget = null;
    }
    expect(playerLines, greaterThan(0));
    expect(pollLines, 0);
  });
}
