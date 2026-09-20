import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/soundboard_play.dart';

/// The packet a press becomes, and the two rules a listener applies to it.
///
/// Worth testing because both rules exist precisely to hold against a client
/// that is not ours: the decoder runs on whatever bytes turn up on a channel
/// every participant can write to, and the cooldown is the only thing
/// standing between a room and somebody holding a button down. A bug in
/// either looks like nothing at all until it is being used.
void main() {
  List<int> packet(Object? body) => utf8.encode(jsonEncode(body));

  group('reading a press', () {
    test('a well-formed packet from a participant names its clip', () {
      expect(
        SoundboardPlay.soundId(
          data: SoundboardPlay.encode('clip-1'),
          topic: SoundboardPlay.topic,
          fromParticipant: true,
        ),
        'clip-1',
      );
    });

    test('a packet with no sender is dropped', () {
      // The opposite of a move, which is only obeyed *because* it has no
      // sender. Here the sender decides whose cooldown and whose mute apply,
      // so an anonymous one cannot be honoured at all.
      expect(
        SoundboardPlay.soundId(
          data: SoundboardPlay.encode('clip-1'),
          topic: SoundboardPlay.topic,
          fromParticipant: false,
        ),
        isNull,
      );
    });

    test('another feature\'s topic is not ours to act on', () {
      expect(
        SoundboardPlay.soundId(
          data: SoundboardPlay.encode('clip-1'),
          topic: 'rift.move',
          fromParticipant: true,
        ),
        isNull,
      );
    });

    test('a newer version is ignored rather than guessed at', () {
      expect(
        SoundboardPlay.soundId(
          data: packet({'v': 2, 'type': 'sound', 'id': 'clip-1'}),
          topic: SoundboardPlay.topic,
          fromParticipant: true,
        ),
        isNull,
      );
    });

    test('rubbish on the wire is an ordinary event, not an error', () {
      for (final data in [
        <int>[0xff, 0xfe, 0x00],
        packet('a string'),
        packet({'type': 'sound'}),
        packet({'v': 1, 'type': 'sound', 'id': ''}),
        packet({'v': 1, 'type': 'sound', 'id': 42}),
        packet({'v': 1, 'type': 'move', 'id': 'clip-1'}),
      ]) {
        expect(
          SoundboardPlay.soundId(
            data: data,
            topic: SoundboardPlay.topic,
            fromParticipant: true,
          ),
          isNull,
        );
      }
    });
  });

  group('the cooldown', () {
    late SoundboardGate gate;
    final start = DateTime(2026, 9, 20, 12);

    setUp(() => gate = SoundboardGate());

    test('the first press from somebody is always heard', () {
      expect(gate.admit('sam', start), isTrue);
    });

    test('a second press inside the window is not', () {
      gate.admit('sam', start);
      expect(
        gate.admit('sam', start.add(SoundboardPlay.cooldown ~/ 2)),
        isFalse,
      );
    });

    test('and once the window has passed it is', () {
      gate.admit('sam', start);
      expect(
        gate.admit(
          'sam',
          start.add(SoundboardPlay.cooldown + const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
    });

    test('a refused press does not push the window out', () {
      // The bug this guards: recording the *attempt* rather than the play
      // means somebody holding the button down is never heard again, because
      // each refusal resets the clock they are being measured against.
      gate.admit('sam', start);
      for (var ms = 100; ms < 1200; ms += 100) {
        gate.admit('sam', start.add(Duration(milliseconds: ms)));
      }
      expect(
        gate.admit(
          'sam',
          start.add(SoundboardPlay.cooldown + const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
    });

    test('one person being held off does not hold off anybody else', () {
      gate.admit('sam', start);
      expect(gate.admit('alex', start), isTrue);
    });

    test('clearing it forgets everybody', () {
      gate.admit('sam', start);
      gate.clear();
      expect(gate.admit('sam', start), isTrue);
    });
  });
}
