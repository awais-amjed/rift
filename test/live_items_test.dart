import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/panel_block.dart';
import 'package:rift/data/classes/poll.dart';
import 'package:rift/logic/cubits/channel_chat/channel_chat_cubit.dart';
import 'package:rift/logic/services/live_items.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);

  ChatMessage message(
    String id, {
    Duration? closesIn,
    String text = '',
    bool locked = false,
    bool pending = false,
  }) => ChatMessage(
    id: id,
    authorId: 'a',
    authorName: 'A',
    text: text,
    sentAt: now,
    isMine: false,
    isLocked: locked,
    isPending: pending,
    poll: closesIn == null
        ? null
        : Poll(
            question: 'Q$id',
            options: const ['x', 'y'],
            multiple: false,
            closesAt: now.add(closesIn),
          ),
  );

  group('merge', () {
    test('merge uses the loaded page when the server has no answer', () {
      final merged = LiveItems.merge(
        fromServer: null,
        loaded: [
          message('5', closesIn: const Duration(hours: 1)),
          message('4'),
          message('3', closesIn: const Duration(hours: 2)),
        ],
      );
      expect(merged.map((m) => m.id), ['5', '3']);
    });

    test('merge takes a live panel from the loaded page, and no other', () {
      ChatMessage panel(String id, {required bool live}) => ChatMessage(
        id: id,
        authorId: 'bot',
        authorName: 'DJ',
        text: '',
        sentAt: now,
        isMine: false,
        panel: Panel.tryParse({
          'v': 1,
          'live': live,
          'blocks': [
            {'type': 'heading', 'text': 'Now playing'},
          ],
        }),
      );
      final merged = LiveItems.merge(
        fromServer: null,
        loaded: [panel('2', live: true), panel('1', live: false)],
      );
      expect(merged.map((m) => m.id), ['2']);
    });

    test(
      'the page\'s copy replaces the server\'s even once it is not live',
      () {
        Panel? blocks({required bool live}) => Panel.tryParse({
          'v': 1,
          'live': live,
          'blocks': [
            {'type': 'heading', 'text': 'Now playing'},
          ],
        });
        ChatMessage panel({required bool live}) => ChatMessage(
          id: '5',
          authorId: 'bot',
          authorName: 'DJ',
          text: '',
          sentAt: now,
          isMine: false,
          panel: blocks(live: live),
        );
        final merged = LiveItems.merge(
          fromServer: [panel(live: true)],
          loaded: [panel(live: false)],
        );
        expect(merged.single.panel?.live, isFalse);
      },
    );

    test('merge keeps one copy per id, the loaded one', () {
      final merged = LiveItems.merge(
        fromServer: [
          message('7', closesIn: const Duration(hours: 1), text: 'server'),
        ],
        loaded: [
          message('7', closesIn: const Duration(hours: 1), text: 'loaded'),
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single.text, 'loaded');
    });

    test('merge orders newest first', () {
      final merged = LiveItems.merge(
        fromServer: [
          message('9', closesIn: const Duration(hours: 1)),
          message('2', closesIn: const Duration(hours: 1)),
        ],
        loaded: [message('10', closesIn: const Duration(hours: 1))],
      );
      expect(merged.map((m) => m.id), ['10', '9', '2']);
    });
  });

  group('open polls', () {
    test('openPolls drops a closed poll and a locked one', () {
      final open = LiveItems.openPolls([
        message('4', closesIn: const Duration(hours: 1)),
        message('3', closesIn: const Duration(hours: -1)),
        message('2', closesIn: const Duration(hours: 1), locked: true),
        message('1', closesIn: const Duration(hours: 1), pending: true),
        message('0'),
      ], now);
      expect(open.map((m) => m.id), ['4']);
    });

    test('a poll leaves the bar when it closes', () {
      final live = [message('1', closesIn: const Duration(seconds: 1))];
      expect(LiveItems.openPolls(live, now), hasLength(1));
      expect(
        LiveItems.openPolls(live, now.add(const Duration(seconds: 2))),
        isEmpty,
      );
    });

    test('nextClose is the soonest future close', () {
      final polls = [
        message('3', closesIn: const Duration(hours: 5)),
        message('2', closesIn: const Duration(minutes: 30)),
        message('1', closesIn: const Duration(hours: -1)),
      ];
      expect(
        LiveItems.nextClose(polls, now),
        now.add(const Duration(minutes: 30)),
      );
      expect(LiveItems.nextClose(const [], now), isNull);
    });
  });

  group('the chat state', () {
    test('live rows are part of its equality', () {
      final poll = message('1', closesIn: const Duration(hours: 1));
      expect(
        ChannelChatState(live: [poll]),
        isNot(equals(const ChannelChatState())),
      );
    });

    test('messageById looks in the loaded page, then in live', () {
      final loaded = message('2', text: 'loaded');
      final old = message('1', closesIn: const Duration(hours: 1));
      final state = ChannelChatState(messages: [loaded], live: [old]);
      expect(state.messageById('2'), loaded);
      expect(state.messageById('1'), old);
      expect(state.messageById('3'), isNull);
    });
  });

  group('live panels', () {
    ChatMessage panel(String id, {String bot = 'dj', bool live = true}) =>
        ChatMessage(
          id: id,
          authorId: bot,
          authorName: 'DJ',
          text: '',
          sentAt: now,
          isMine: false,
          panel: Panel.tryParse({
            'v': 1,
            'live': live,
            'blocks': [
              {'type': 'heading', 'text': 'Now playing'},
            ],
          }),
        );

    test('an offline bot\'s live panel stays in the history', () {
      final live = [panel('9', bot: 'gone'), panel('8')];
      final shown = LiveItems.shownPanels(
        live,
        onlineIds: {'dj'},
        onlineKnown: true,
      );
      expect(shown.map((m) => m.id), ['8']);
      final history = [panel('9', bot: 'gone'), message('7'), panel('8')];
      expect(LiveItems.hideShown(history, shown).map((m) => m.id), ['9', '7']);
    });

    test('a bot\'s older live panel is left in the history', () {
      // A bot that crashed and came back posts a new player; the one it never
      // got to clear is from a session that is over.
      final live = [panel('9'), panel('8', bot: 'other'), panel('3')];
      final shown = LiveItems.shownPanels(
        live,
        onlineIds: {'dj', 'other'},
        onlineKnown: true,
      );
      expect(shown.map((m) => m.id), ['9', '8']);
    });

    test('a player is for the people in its bot\'s call', () {
      final shown = [panel('9'), panel('8', bot: 'other')];
      List<String> forCall(Set<String> call) => LiveItems.forCall(
        shown,
        callUserIds: call,
        voiceUserIds: {'dj', 'other'},
      ).map((m) => m.id).toList();
      expect(forCall({'me', 'dj'}), ['9']);
      expect(forCall(const {}), isEmpty);
      // Out of the call it is in neither place: the history still leaves it out.
      final history = [panel('9'), message('7')];
      expect(LiveItems.hideShown(history, shown).map((m) => m.id), ['7']);
    });

    test('a bot in no call shows its live panel to everyone', () {
      expect(
        LiveItems.forCall(
          [panel('9', bot: 'scores')],
          callUserIds: const {},
          voiceUserIds: {'dj'},
        ).map((m) => m.id),
        ['9'],
      );
    });

    test('the call\'s players join the bar in any channel', () {
      final here = [panel('5', bot: 'scores')];
      // The call's player, read from the channel it was posted in.
      final fromCall = [panel('9')];
      expect(LiveItems.withCallPanels(here, fromCall).map((m) => m.id), [
        '9',
        '5',
      ]);
    });

    test('a call\'s player in the open channel is in the bar once', () {
      // Here it is the page's copy, which a redraw reaches first.
      final here = [panel('9', live: true)];
      expect(
        LiveItems.withCallPanels(here, [
          panel('9'),
          panel('7'),
        ]).map((m) => m.id),
        ['9'],
      );
    });

    test('a channel\'s rows give the call\'s live players only', () {
      final rows = [
        panel('9'),
        panel('8', live: false),
        panel('7', bot: 'other'),
        message('6', closesIn: const Duration(hours: 1)),
      ];
      expect(
        LiveItems.callPanels(
          rows,
          callUserIds: {'me', 'dj'},
          botIds: {'dj', 'other'},
        ).map((m) => m.id),
        ['9'],
      );
    });

    test('a call\'s player is a bot\'s: a member in the call draws none', () {
      // A server before 024 let a member write blocks onto their own plain
      // message, and a call named there reached everybody in the call.
      final rows = [panel('9', bot: 'me'), panel('8')];
      expect(
        LiveItems.callPanels(
          rows,
          callUserIds: {'me', 'dj'},
          botIds: {'dj'},
        ).map((m) => m.id),
        ['8'],
      );
    });

    test('unknown presence shows nothing in the bar', () {
      expect(
        LiveItems.shownPanels(
          [panel('8')],
          onlineIds: {'dj'},
          onlineKnown: false,
        ),
        isEmpty,
      );
    });

    test('a panel without live is never shown', () {
      expect(
        LiveItems.shownPanels(
          [panel('8', live: false), message('5', closesIn: Duration.zero)],
          onlineIds: {'dj', 'a'},
          onlineKnown: true,
        ),
        isEmpty,
      );
    });

    test('hideShown returns the same list when nothing is shown', () {
      final history = [message('2'), panel('1', live: false)];
      expect(
        identical(LiveItems.hideShown(history, const []), history),
        isTrue,
      );
      // Nor when what is shown is not on this page.
      expect(
        identical(LiveItems.hideShown(history, [panel('40')]), history),
        isTrue,
      );
    });
  });
}
