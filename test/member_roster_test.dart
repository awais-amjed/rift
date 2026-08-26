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

void main() {
  group('MemberRoster.split', () {
    test('groups by presence', () {
      final result = MemberRoster.split(
        [member('1', 'Ana'), member('2', 'Bo'), member('3', 'Cy')],
        {'1', '3'},
      );
      expect(result.online.map((m) => m.displayName), ['Ana', 'Cy']);
      expect(result.offline.map((m) => m.displayName), ['Bo']);
    });

    test('sorts each group by display name, case-insensitively', () {
      final result = MemberRoster.split(
        [member('1', 'zoe'), member('2', 'Ana'), member('3', 'mia')],
        {'1', '2', '3'},
      );
      expect(result.online.map((m) => m.displayName), ['Ana', 'mia', 'zoe']);
    });

    test('drops banned members from both groups', () {
      final result = MemberRoster.split(
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
      final result = MemberRoster.split([member('1', 'Ana')], {'1', 'ghost'});
      expect(result.online, hasLength(1));
      expect(result.offline, isEmpty);
    });

    test('nobody online puts everyone in offline', () {
      final result = MemberRoster.split([
        member('1', 'Ana'),
        member('2', 'Bo'),
      ], const {});
      expect(result.online, isEmpty);
      expect(result.offline, hasLength(2));
    });

    test('an empty member list yields two empty groups', () {
      final result = MemberRoster.split(const [], {'1'});
      expect(result.online, isEmpty);
      expect(result.offline, isEmpty);
    });
  });

  group('bots', () {
    test('are their own group, not sorted among the people', () {
      // BOTS.md §9: the separation is structural because the difference is —
      // a bot cannot be handed a channel key and hears only what it is told.
      final result = MemberRoster.split(
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
      final result = MemberRoster.split(
        [member('2', 'MusicBot', isBot: true)],
        {'2'},
      );

      expect(result.bots, hasLength(1));
      expect(result.online, isEmpty);
    });

    test('a banned bot is dropped like anybody else', () {
      final result = MemberRoster.split([
        member('2', 'OldBot', isBot: true, isBanned: true),
      ], {});
      expect(result.bots, isEmpty);
    });

    test('bots sort by display name too', () {
      final result = MemberRoster.split([
        member('1', 'zeta', isBot: true),
        member('2', 'Alpha', isBot: true),
      ], {});
      expect(result.bots.map((m) => m.displayName), ['Alpha', 'zeta']);
    });
  });

  group('the bot flag itself', () {
    test('survives copyWith and cannot be flipped by it', () {
      // Pinned server-side by a trigger (migration 014); copyWith exposing it
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
}
