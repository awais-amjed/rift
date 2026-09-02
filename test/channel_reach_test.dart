import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/bot_command.dart';
import 'package:rift/logic/services/channel_reach.dart';

ServerMember _person(String username) => ServerMember(
  id: username,
  username: username,
  displayName: username,
  permissions: const UserPermissions(),
);

ServerMember _bot(String username, {bool isBanned = false}) => ServerMember(
  id: username,
  username: username,
  displayName: username,
  permissions: const UserPermissions(),
  isBot: true,
  isBanned: isBanned,
);

void main() {
  final roster = [_person('sam'), _bot('musicbot'), _bot('gone', isBanned: true)];

  group('who a channel reaches', () {
    test('a null audience is everybody — a public channel', () {
      expect(ChannelReach.within(roster, null).length, 3);
    });

    test('an audience narrows to itself, and never widens', () {
      expect(
        ChannelReach.within(roster, {'sam', 'ghost'}).map((m) => m.id),
        ['sam'],
      );
    });
  });

  group('the bots a slash can reach', () {
    test('a public channel reaches every bot that is not banned', () {
      expect(ChannelReach.botsIn(roster, null).map((m) => m.id), ['musicbot']);
    });

    test('a private channel with no bot in it reaches none', () {
      // `set_channel_members` refuses to seat a bot, so unless a role put one
      // here `messages_select` never returns the command: `can_see_channel` is
      // asked before `to_bot`. The row would sit in the clear, unread.
      expect(ChannelReach.botsIn(roster, {'sam'}), isEmpty);
    });

    test('a bot a role let in is reachable again', () {
      expect(
        ChannelReach.botsIn(roster, {'sam', 'musicbot'}).map((m) => m.id),
        ['musicbot'],
      );
    });

    test('a banned bot is never offered, in either kind of channel', () {
      // `app.is_addressable_bot` refuses a command sent to one, so offering it
      // would be offering a send that comes back rejected.
      expect(
        ChannelReach.botsIn(roster, {'sam', 'gone'}).map((m) => m.id),
        isEmpty,
      );
    });
  });

  group('an unreachable bot does not make a message plaintext', () {
    test('a command to a bot in the room parses, and goes out in the clear', () {
      final command = BotCommands.parse(
        '/musicbot play something',
        ChannelReach.botsIn(roster, {'sam', 'musicbot'}),
      );
      expect(command?.bot.id, 'musicbot');
    });

    test('the same line in a room the bot cannot see is just a message', () {
      // The important half. `parse` returning null is what sends this sealed
      // rather than as a plaintext row addressed to somebody who will never be
      // handed it — a slash that reaches no bot is just a slash.
      final command = BotCommands.parse(
        '/musicbot play something',
        ChannelReach.botsIn(roster, {'sam'}),
      );
      expect(command, isNull);
    });
  });
}
