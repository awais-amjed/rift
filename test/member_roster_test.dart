import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/member_roster.dart';

ServerMember member(
  String id,
  String name, {
  bool isBanned = false,
  bool isBot = false,
  UserPermissions permissions = const UserPermissions(),
}) => ServerMember(
  id: id,
  username: name.toLowerCase(),
  displayName: name,
  permissions: permissions,
  isBanned: isBanned,
  isBot: isBot,
);

/// The old call shape, kept as a helper: most of these cases are about one
/// list of members and who is online, and spelling out four named arguments in
/// each would bury what the case is actually testing.
///
/// Bots are lifted out because the sidebar now fetches them separately, and
/// people go in as the paged list, which is where the offline group comes from.
({
  List<ServerMember> bots,
  List<ServerMember> online,
  List<ServerMember> offline,
})
split(List<ServerMember> members, Set<String> onlineIds) => MemberRoster.split(
  bots: [
    for (final m in members)
      if (m.isBot) m,
  ],
  known: members,
  people: [
    for (final m in members)
      if (!m.isBot) m,
  ],
  onlineIds: onlineIds,
);

void main() {
  group('MemberRoster.split', () {
    test('groups by presence', () {
      final result = split(
        [member('1', 'Ana'), member('2', 'Bo'), member('3', 'Cy')],
        {'1', '3'},
      );
      expect(result.online.map((m) => m.displayName), ['Ana', 'Cy']);
      expect(result.offline.map((m) => m.displayName), ['Bo']);
    });

    test('sorts each group by display name, case-insensitively', () {
      final result = split(
        [member('1', 'zoe'), member('2', 'Ana'), member('3', 'mia')],
        {'1', '2', '3'},
      );
      expect(result.online.map((m) => m.displayName), ['Ana', 'mia', 'zoe']);
    });

    test('drops banned members from both groups', () {
      final result = split(
        [
          member('1', 'Ana', isBanned: true),
          member('2', 'Bo', isBanned: true),
          member('3', 'Cy'),
        ],
        {'1', '3'},
      );
      expect(result.online.map((m) => m.id), ['3']);
      expect(result.offline, isEmpty);
    });

    test('an online id with no member row is ignored, not invented', () {
      final result = split([member('1', 'Ana')], {'1', 'ghost'});
      expect(result.online, hasLength(1));
      expect(result.offline, isEmpty);
    });

    test('nobody online puts everyone in offline', () {
      final result = split([member('1', 'Ana'), member('2', 'Bo')], const {});
      expect(result.online, isEmpty);
      expect(result.offline, hasLength(2));
    });

    test('an empty member list yields two empty groups', () {
      final result = split(const [], {'1'});
      expect(result.online, isEmpty);
      expect(result.offline, isEmpty);
    });
  });

  group('bots', () {
    test('are their own group, not sorted among the people', () {
      // BOTS.md §9: the separation is structural because the difference is —
      // a bot cannot be handed a channel key and hears only what it is told.
      final result = split(
        [
          member('1', 'Ana'),
          member('2', 'MusicBot', isBot: true),
          member('3', 'Bo'),
        ],
        {'1', '2'},
      );

      expect(result.bots.map((m) => m.displayName), ['MusicBot']);
      expect(result.online.map((m) => m.displayName), ['Ana']);
      expect(result.offline.map((m) => m.displayName), ['Bo']);
    });

    test('a connected bot is still a bot, not an online member', () {
      // Presence says a bot is running. It does not make it a person in the
      // room, and grouping it as one would put it beside the conversation it
      // cannot hear.
      final result = split([member('2', 'MusicBot', isBot: true)], {'2'});

      expect(result.bots, hasLength(1));
      expect(result.online, isEmpty);
    });

    test('a banned bot is dropped like anybody else', () {
      final result = split([
        member('2', 'OldBot', isBot: true, isBanned: true),
      ], {});
      expect(result.bots, isEmpty);
    });

    test('bots sort by display name too', () {
      final result = split([
        member('1', 'zeta', isBot: true),
        member('2', 'Alpha', isBot: true),
      ], {});
      expect(result.bots.map((m) => m.displayName), ['Alpha', 'zeta']);
    });
  });

  group('the bot flag itself', () {
    test('survives copyWith and cannot be flipped by it', () {
      // Pinned server-side by a trigger (`005_bots.sql`); copyWith exposing it
      // would be the one place in the client a person becomes a program.
      final bot = member('1', 'MusicBot', isBot: true);
      expect(bot.copyWith(isBanned: true).isBot, isTrue);

      final human = member('2', 'Ana');
      expect(human.copyWith(isMuted: true).isBot, isFalse);
    });

    test('is read from the row, defaulting to a person', () {
      expect(
        ServerMember.fromJson({
          'id': '1',
          'username': 'ana',
          'display_name': 'Ana',
        }).isBot,
        isFalse,
      );
      expect(
        ServerMember.fromJson({
          'id': '2',
          'username': 'bot',
          'display_name': 'Bot',
          'is_bot': true,
        }).isBot,
        isTrue,
      );
    });
  });

  group('when they joined', () {
    test('is read from the row and kept through copyWith', () {
      final parsed = ServerMember.fromJson({
        'id': '1',
        'username': 'ana',
        'display_name': 'Ana',
        'joined_at': '2026-09-06T20:46:32.016884+00:00',
      });
      expect(parsed.joinedAt, DateTime.utc(2026, 9, 6, 20, 46, 32, 16, 884));
      // The profile draws it beside three moderation buttons, and every one
      // of them rebuilds the row through copyWith.
      expect(parsed.copyWith(isMuted: true).joinedAt, parsed.joinedAt);
    });

    test('is null on a server too old to send the column', () {
      // `member_directory` gained `joined_at` after the first servers were
      // running. An absent column is "not known", which the profile leaves
      // the line out for — never epoch, which it would print as 1970.
      final parsed = ServerMember.fromJson({
        'id': '1',
        'username': 'ana',
        'display_name': 'Ana',
      });
      expect(parsed.joinedAt, isNull);
    });
  });

  group('a paged roster', () {
    test('somebody online but not yet paged in still shows as online', () {
      // The case the split exists for. Presence names an id; the pages have not
      // reached that letter yet; the sidebar must still draw them rather than
      // wait for a scroll that may never happen.
      final result = MemberRoster.split(
        bots: const [],
        known: [member('9', 'Zoe')],
        people: [member('1', 'Ana')],
        onlineIds: {'9'},
      );

      expect(result.online.map((m) => m.displayName), ['Zoe']);
      expect(result.offline.map((m) => m.displayName), ['Ana']);
    });

    test(
      'but an offline member nobody paged in is not wedged into the list',
      () {
        // Resolving somebody by id — an author in the scrollback, say — must not
        // insert them into the middle of an alphabet the reader is scrolling.
        final result = MemberRoster.split(
          bots: const [],
          known: [member('9', 'Zoe')],
          people: [member('1', 'Ana')],
          onlineIds: const {},
        );

        expect(result.offline.map((m) => m.displayName), ['Ana']);
      },
    );

    test('somebody in both lists is drawn once', () {
      final result = MemberRoster.split(
        bots: const [],
        known: [member('1', 'Ana')],
        people: [member('1', 'Ana')],
        onlineIds: {'1'},
      );

      expect(result.online, hasLength(1));
      expect(result.offline, isEmpty);
    });

    test('bots come from their own fetch, not from the pages', () {
      final result = MemberRoster.split(
        bots: [member('b', 'MusicBot', isBot: true)],
        known: const [],
        people: [member('1', 'Ana')],
        onlineIds: const {},
      );

      expect(result.bots.map((m) => m.displayName), ['MusicBot']);
      expect(result.offline.map((m) => m.displayName), ['Ana']);
    });
  });
}
