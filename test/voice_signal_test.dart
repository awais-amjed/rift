import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/voice_signal.dart';

List<int> _packet(Map<String, dynamic> body) => utf8.encode(jsonEncode(body));

List<int> _move({String channelId = 'chan-2', int version = 1}) =>
    _packet({'v': version, 'type': 'move', 'channel_id': channelId});

void main() {
  group('a move signal', () {
    test('names the channel to join', () {
      expect(
        VoiceSignal.moveDestination(
          data: _move(),
          topic: VoiceSignal.moveTopic,
          fromServer: true,
        ),
        'chan-2',
      );
    });

    test('is refused when a member sent it', () {
      // The whole authorisation check: only the API can send without a sender,
      // and only the API knows the moderator asked for this.
      expect(
        VoiceSignal.moveDestination(
          data: _move(),
          topic: VoiceSignal.moveTopic,
          fromServer: false,
        ),
        isNull,
      );
    });

    test('is refused on another topic', () {
      expect(
        VoiceSignal.moveDestination(
          data: _move(),
          topic: 'chat',
          fromServer: true,
        ),
        isNull,
      );
      expect(
        VoiceSignal.moveDestination(
          data: _move(),
          topic: null,
          fromServer: true,
        ),
        isNull,
      );
    });

    test('is refused from a version we do not know', () {
      expect(
        VoiceSignal.moveDestination(
          data: _move(version: VoiceSignal.version + 1),
          topic: VoiceSignal.moveTopic,
          fromServer: true,
        ),
        isNull,
      );
    });
  });

  group('anything else on the data channel', () {
    test('is ignored rather than thrown over', () {
      final rubbish = <List<int>>[
        const [],
        const [0xff, 0xfe, 0x00], // not UTF-8
        utf8.encode('hello'), // not JSON
        utf8.encode('[1,2,3]'), // JSON, but not an object
        _packet({'v': 1, 'type': 'wave', 'channel_id': 'chan-2'}),
        _packet({'v': 1, 'type': 'move'}), // no destination
        _packet({'v': 1, 'type': 'move', 'channel_id': ''}),
        _packet({'v': 1, 'type': 'move', 'channel_id': 42}),
      ];

      for (final data in rubbish) {
        expect(
          VoiceSignal.moveDestination(
            data: data,
            topic: VoiceSignal.moveTopic,
            fromServer: true,
          ),
          isNull,
          reason: 'should have ignored $data',
        );
      }
    });
  });
}
