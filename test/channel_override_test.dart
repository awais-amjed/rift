import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/channel_override.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/enums/server_permission.dart';

void main() {
  group('ChannelOverride', () {
    test('reads the row the server stores', () {
      final o = ChannelOverride.fromJson({
        'role_id': 'r1',
        'allow': ServerPermission.attachFiles.mask,
        'deny': ServerPermission.sendMessages.mask,
      });
      expect(o.stateOf(ServerPermission.attachFiles), OverrideState.allow);
      expect(o.stateOf(ServerPermission.sendMessages), OverrideState.deny);
      expect(o.stateOf(ServerPermission.addReactions), OverrideState.inherit);
      expect(ChannelOverride.fromJson(o.toJson()), o);
    });

    test('moving one bit leaves the others, and never both ways at once', () {
      const start = ChannelOverride(roleId: 'r1');
      final denied = start
          .withState(ServerPermission.sendMessages, OverrideState.allow)
          .withState(ServerPermission.addReactions, OverrideState.deny)
          .withState(ServerPermission.sendMessages, OverrideState.deny);
      expect(denied.allow, 0);
      expect(
        denied.deny,
        ServerPermission.sendMessages.mask | ServerPermission.addReactions.mask,
      );
      final cleared = denied
          .withState(ServerPermission.sendMessages, OverrideState.inherit)
          .withState(ServerPermission.addReactions, OverrideState.inherit);
      expect(cleared.isEmpty, isTrue);
    });

    test('a channel offers only its own kind of bits, never View channel', () {
      final text = ChannelOverride.overridableIn(ChannelType.text);
      final voice = ChannelOverride.overridableIn(ChannelType.voice);
      expect(text, contains(ServerPermission.sendMessages));
      expect(voice, contains(ServerPermission.speak));
      expect(text.toSet().intersection(voice.toSet()), isEmpty);
      expect([...text, ...voice], isNot(contains(ServerPermission.viewChannel)));
      for (final p in [...text, ...voice]) {
        expect(p.group, isNot(PermissionGroup.server), reason: p.name);
      }
    });

    test('Default is the server\'s bit, after the @everyone row here', () {
      const send = ServerPermission.sendMessages;
      final everyone = send.mask;
      // @everyone's own row: just the server role.
      expect(ChannelOverride.defaultFor(send, serverBits: everyone), isTrue);
      expect(ChannelOverride.defaultFor(send, serverBits: 0), isFalse);

      // Another role's row: @everyone's row here applies first.
      final readOnly = const ChannelOverride(
        roleId: 'ev',
      ).withState(send, OverrideState.deny);
      expect(
        ChannelOverride.defaultFor(
          send,
          serverBits: everyone,
          everyoneRow: readOnly,
        ),
        isFalse,
      );
      final opened = const ChannelOverride(
        roleId: 'ev',
      ).withState(send, OverrideState.allow);
      expect(
        ChannelOverride.defaultFor(send, serverBits: 0, everyoneRow: opened),
        isTrue,
      );
      expect(
        ChannelOverride.defaultFor(
          send,
          serverBits: ServerPermission.administrator.mask,
          everyoneRow: readOnly,
        ),
        isTrue,
      );

      // A role's own answer beats the default; leaving it alone is the default.
      final djs = const ChannelOverride(
        roleId: 'dj',
      ).withState(send, OverrideState.allow);
      expect(
        ChannelOverride.resultFor(
          send,
          row: djs,
          serverBits: everyone,
          everyoneRow: readOnly,
        ),
        isTrue,
      );
      expect(
        ChannelOverride.resultFor(
          send,
          row: const ChannelOverride(roleId: 'dj'),
          serverBits: everyone,
          everyoneRow: readOnly,
        ),
        isFalse,
      );
    });

    test('what goes out in a message needs Send; what happens in a call, '
        'Join', () {
      for (final p in [
        ServerPermission.attachFiles,
        ServerPermission.createPolls,
        ServerPermission.mentionAll,
      ]) {
        expect(ChannelOverride.needs(p), ServerPermission.sendMessages);
      }
      for (final p in [
        ServerPermission.speak,
        ServerPermission.screenShare,
        ServerPermission.useSoundboard,
      ]) {
        expect(ChannelOverride.needs(p), ServerPermission.connect);
      }
      for (final p in [
        ServerPermission.addReactions,
        ServerPermission.pinMessages,
        ServerPermission.manageMessages,
        ServerPermission.summonBots,
        ServerPermission.sendMessages,
        ServerPermission.connect,
      ]) {
        expect(ChannelOverride.needs(p), isNull, reason: p.name);
      }
    });
  });

  group('UserPermissions.inChannel', () {
    final server = UserPermissions(
      bits:
          ServerPermission.sendMessages.mask |
          ServerPermission.addReactions.mask,
    );

    test('a channel from a server without overrides is the server', () {
      const old = Channel(id: 'c', name: 'news', channelType: ChannelType.text);
      expect(server.inChannel(old), server);
      expect(server.inChannel(null), server);
    });

    test('a channel that says what we may do is the answer', () {
      final news = Channel(
        id: 'c',
        name: 'news',
        channelType: ChannelType.text,
        myPermissions: ServerPermission.addReactions.mask,
      );
      final here = server.inChannel(news);
      expect(here.can(ServerPermission.sendMessages), isFalse);
      expect(here.can(ServerPermission.addReactions), isTrue);
    });

    test('the channel bits survive a round trip through the saved state', () {
      final news = Channel(
        id: 'c',
        name: 'news',
        channelType: ChannelType.text,
        myPermissions: 5,
      );
      expect(Channel.fromJson(news.toJson()), news);
    });
  });
}
