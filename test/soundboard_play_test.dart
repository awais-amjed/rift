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

  group('how loud, and what silences it', () {
    double volume({
      bool deafened = false,
      bool muted = false,
      double globalVolume = 0.6,
      bool fromSelf = false,
      bool personMuted = false,
      double personVolume = 1.0,
    }) => SoundboardVolume.resolve(
      deafened: deafened,
      muted: muted,
      globalVolume: globalVolume,
      fromSelf: fromSelf,
      personMuted: personMuted,
      personVolume: personVolume,
    );

    test('somebody else\'s clip plays at this device\'s volume', () {
      expect(volume(), 0.6);
    });

    test('muting the soundboard silences them', () {
      expect(volume(muted: true), 0);
    });

    test('...and does not silence a clip we pressed ourselves', () {
      // The rule the preview button always followed and the press did not:
      // both are clips this device asked for. You should hear what you have
      // just put into the room, since everyone else is about to.
      expect(volume(muted: true, fromSelf: true), 0.6);
    });

    test('being deafened silences everything, our own included', () {
      expect(volume(deafened: true), 0);
      expect(volume(deafened: true, fromSelf: true), 0);
    });

    test('muting one person leaves everybody else alone', () {
      expect(volume(personMuted: true), 0);
      expect(volume(personMuted: false), 0.6);
    });

    test('their volume multiplies this device\'s, it does not replace it', () {
      expect(volume(globalVolume: 0.5, personVolume: 0.5), 0.25);
    });

    test('no per-person setting reaches a clip of our own', () {
      // `fromSelf` short-circuits before them, which is what stops a mute we
      // set against ourselves from ever mattering.
      expect(volume(fromSelf: true, personMuted: true), 0.6);
    });

    test('the answer is always a volume, never out of range', () {
      expect(volume(globalVolume: 4, personVolume: 4), 1.0);
      expect(volume(globalVolume: 4, fromSelf: true), 1.0);
    });
  });
}
