import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/channel_presence/channel_presence_cubit.dart';
import 'package:rift/logic/services/voice_move.dart';

Channel _voice(String id, String name) =>
    Channel(id: id, name: name, channelType: ChannelType.voice);

Channel _text(String id, String name) =>
    Channel(id: id, name: name, channelType: ChannelType.text);

final _channels = [
  _text('t1', 'general'),
  _voice('v1', 'Lounge'),
  _text('t2', 'links'),
  _voice('v2', 'Gaming'),
  _voice('v3', 'AFK'),
];

void main() {
  group('move destinations', () {
    test('are the voice channels, in sidebar order', () {
      expect(VoiceMove.destinations(_channels).map((c) => c.name), [
        'Lounge',
        'Gaming',
        'AFK',
      ]);
    });

    test('leave out the channel they are already in', () {
      expect(VoiceMove.destinations(_channels, from: 'v2').map((c) => c.name), [
        'Lounge',
        'AFK',
      ]);
    });

    test('are empty when the only voice channel is theirs', () {
      expect(
        VoiceMove.destinations([
          _text('t1', 'general'),
          _voice('v1', 'Lounge'),
        ], from: 'v1'),
        isEmpty,
      );
    });
  });

  group('presence', () {
    const state = ChannelPresenceState(
      channelPresence: {
        'v1': [PresenceUser(userId: 'u1', displayName: 'Ada')],
        'v2': [
          PresenceUser(userId: 'u2', displayName: 'Grace'),
          PresenceUser(userId: 'u3', displayName: 'Alan'),
        ],
      },
      onlineUserIds: {'u1', 'u2', 'u3', 'u4'},
    );

    test('says which call a member is in', () {
      expect(state.channelOf('u3'), 'v2');
      expect(state.channelOf('u1'), 'v1');
    });

    test('says nothing for someone online but not in voice', () {
      // Which is what hides "Move to": there is no connection to tell.
      expect(state.channelOf('u4'), isNull);
    });
  });
}
