import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/voice_locations.dart';

void main() {
  group('the wire format', () {
    test('round-trips a location', () {
      final delta = VoiceLocations.decode(
        VoiceLocations.encode(userId: 'u1', channelId: 'general'),
      );

      expect(delta?.userId, 'u1');
      expect(delta?.channelId, 'general');
    });

    test('round-trips leaving voice', () {
      // Null is a value here, not an omission — it's how "I left" is said.
      final delta = VoiceLocations.decode(
        VoiceLocations.encode(userId: 'u1', channelId: null),
      );

      expect(delta?.userId, 'u1');
      expect(delta?.channelId, isNull);
    });

    test('unwraps the envelope Realtime puts around a broadcast', () {
      final delta = VoiceLocations.decode({
        'event': VoiceLocations.event,
        'type': 'broadcast',
        'payload': VoiceLocations.encode(userId: 'u1', channelId: 'general'),
      });

      expect(delta?.channelId, 'general');
    });

    test('refuses anything it does not recognise', () {
      for (final message in <Map<String, dynamic>>[
        {},
        {'v': 99, 'userId': 'u1', 'channelId': 'general'},
        {'v': 1, 'channelId': 'general'},
        {'v': 1, 'userId': '', 'channelId': 'general'},
        {'v': 1, 'userId': 'u1', 'channelId': 7},
        {'v': 1, 'userId': 'u1', 'channelId': ''},
      ]) {
        expect(VoiceLocations.decode(message), isNull, reason: '$message');
      }
    });

    test('gives each server its own topic', () {
      expect(VoiceLocations.topic('s1'), isNot(VoiceLocations.topic('s2')));
    });
  });

  group('sharing', () {
    test('round-trips a screen up', () {
      final delta = VoiceLocations.decode(
        VoiceLocations.encode(
          userId: 'u1',
          channelId: 'general',
          sharing: true,
        ),
      );

      expect(delta?.sharing, isTrue);
    });

    test('says nothing extra when nothing is shared', () {
      // The same message an older app and every bot send.
      final message = VoiceLocations.encode(userId: 'u1', channelId: 'general');

      expect(message.containsKey('sharing'), isFalse);
      expect(VoiceLocations.decode(message)?.sharing, isFalse);
    });

    test('leaving voice takes the share with it', () {
      final delta = VoiceLocations.decode({
        'v': 1,
        'userId': 'u1',
        'channelId': null,
        'sharing': true,
      });

      expect(delta?.sharing, isFalse);
      expect(
        VoiceLocations.applySharing(
          const {'u1'},
          userId: 'u1',
          channelId: null,
          sharing: true,
        ),
        isEmpty,
      );
    });

    test('a delta turns a screen on and off', () {
      final on = VoiceLocations.applySharing(
        const {},
        userId: 'u1',
        channelId: 'general',
        sharing: true,
      );
      expect(on, {'u1'});
      expect(
        VoiceLocations.applySharing(
          on,
          userId: 'u1',
          channelId: 'general',
          sharing: false,
        ),
        isEmpty,
      );
    });

    test('a snapshot decides for everyone not heard from since', () {
      final next = VoiceLocations.mergeSharing(
        const {'u2'},
        current: const {'u1'},
        heard: const {},
        locations: const {'u1': 'a', 'u2': 'a'},
      );

      expect(next, {'u2'});
    });

    test('a live delta beats the snapshot it raced', () {
      final next = VoiceLocations.mergeSharing(
        const {'u2'},
        current: const {'u1'},
        heard: const {'u1', 'u2'},
        locations: const {'u1': 'a', 'u2': 'a'},
      );

      expect(next, {'u1'});
    });

    test('a server that does not say keeps what the broadcasts said', () {
      final next = VoiceLocations.mergeSharing(
        null,
        current: const {'u1', 'u2'},
        heard: const {},
        // u2 is no longer in a call.
        locations: const {'u1': 'a'},
      );

      expect(next, {'u1'});
    });
  });

  group('applying a delta', () {
    test('moves someone into a channel', () {
      final next = VoiceLocations.applyDelta(
        const {'u1': 'general'},
        userId: 'u2',
        channelId: 'gaming',
      );

      expect(next, {'u1': 'general', 'u2': 'gaming'});
    });

    test('drops them when they leave voice', () {
      final next = VoiceLocations.applyDelta(
        const {'u1': 'general', 'u2': 'gaming'},
        userId: 'u1',
        channelId: null,
      );

      expect(next, {'u2': 'gaming'});
    });

    test('leaves the map it was given alone', () {
      const current = {'u1': 'general'};

      VoiceLocations.applyDelta(current, userId: 'u1', channelId: null);

      expect(current, {'u1': 'general'});
    });
  });

  group('merging a snapshot', () {
    test('takes the snapshot for everyone we have not heard from', () {
      final next = VoiceLocations.mergeSnapshot(
        const {'u1': 'general', 'u2': 'gaming'},
        current: const {'u1': 'stale'},
        heard: const {},
      );

      expect(next, {'u1': 'general', 'u2': 'gaming'});
    });

    test('lets a live delta beat the snapshot it raced', () {
      // The snapshot was taken before u1 moved, so applying it wholesale would
      // drag them back to where they used to be.
      final next = VoiceLocations.mergeSnapshot(
        const {'u1': 'general'},
        current: const {'u1': 'gaming'},
        heard: const {'u1'},
      );

      expect(next['u1'], 'gaming');
    });

    test('honours a leave that raced the snapshot', () {
      final next = VoiceLocations.mergeSnapshot(
        const {'u1': 'general', 'u2': 'gaming'},
        current: const {'u2': 'gaming'},
        heard: const {'u1'},
      );

      expect(next.containsKey('u1'), isFalse);
      expect(next['u2'], 'gaming');
    });
  });

  group('who a read may not know about yet', () {
    // LiveKit counts a room's people at most every five seconds, and the
    // roster skips a room it counts as empty: a read just after someone
    // opened an empty channel leaves them out. A watching client heard them
    // announce it a second before its 30 s read, took the read, and drew the
    // channel empty for as long as they stayed.
    test('someone heard just before the read was asked', () {
      final heard = VoiceLocations.heardSince(
        const {'u1': Duration(seconds: 59)},
        asked: const Duration(seconds: 60),
      );

      expect(heard, {'u1'});
      final next = VoiceLocations.mergeSnapshot(
        const {},
        current: const {'u1': 'switch-call'},
        heard: heard,
      );
      expect(next, {'u1': 'switch-call'});
    });

    test('someone heard while the read was out', () {
      expect(
        VoiceLocations.heardSince(
          const {'u1': Duration(seconds: 61)},
          asked: const Duration(seconds: 60),
        ),
        {'u1'},
      );
    });

    test('not someone heard long before: the read is the better answer', () {
      // A ghost is somebody whose last word was long ago; the read is what
      // takes them away.
      expect(
        VoiceLocations.heardSince(
          const {'u1': Duration(seconds: 40)},
          asked: const Duration(seconds: 60),
        ),
        isEmpty,
      );
    });
  });

  group('rosters', () {
    test('groups members by the channel they are in', () {
      final rosters = VoiceLocations.rosters(
        locations: const {'u1': 'general', 'u2': 'general', 'u3': 'gaming'},
        online: const {'u1', 'u2', 'u3'},
      );

      expect(rosters['general'], ['u1', 'u2']);
      expect(rosters['gaming'], ['u3']);
    });

    test('forgets anyone presence no longer vouches for', () {
      // The whole reason presence keeps a job: a client that crashed mid-call
      // never got to broadcast that it left, and doesn't have to.
      final rosters = VoiceLocations.rosters(
        locations: const {'u1': 'general', 'u2': 'general'},
        online: const {'u1'},
      );

      expect(rosters['general'], ['u1']);
    });

    test('drops a channel that empties out entirely', () {
      final rosters = VoiceLocations.rosters(
        locations: const {'u1': 'general'},
        online: const {},
      );

      expect(rosters, isEmpty);
    });

    test('leaves the local user out', () {
      final rosters = VoiceLocations.rosters(
        locations: const {'me': 'general', 'u1': 'general'},
        online: const {'me', 'u1'},
        excluding: 'me',
      );

      expect(rosters['general'], ['u1']);
    });
  });

  group('leftSilently', () {
    test('someone gone from the room but still placed in it', () {
      // A bot on an old SDK: placed by a roster read, and leaving says nothing.
      expect(
        VoiceLocations.leftSilently(
          before: {'bot', 'ann'},
          after: {'ann'},
          locations: {'bot': 'c1', 'ann': 'c1'},
          channelId: 'c1',
        ),
        {'bot'},
      );
    });

    test('someone who announced the move is not asked about', () {
      expect(
        VoiceLocations.leftSilently(
          before: {'ann'},
          after: {},
          locations: {'ann': 'c2'},
          channelId: 'c1',
        ),
        isEmpty,
      );
      expect(
        VoiceLocations.leftSilently(
          before: {'ann'},
          after: {},
          locations: {},
          channelId: 'c1',
        ),
        isEmpty,
      );
    });

    test('nobody left, nobody asked about', () {
      expect(
        VoiceLocations.leftSilently(
          before: {'ann'},
          after: {'ann', 'bob'},
          locations: {'ann': 'c1'},
          channelId: 'c1',
        ),
        isEmpty,
      );
    });
  });

  group('what to say while a call connects', () {
    test('a join waits for the room', () {
      // Said at once, everyone drew the joiner in the sidebar a moment before
      // the call's grid did: the token, the key and the connect were still
      // to come.
      expect(
        VoiceLocations.placeToSay(
          channelId: 'c1',
          connected: false,
          said: null,
        ),
        isNull,
      );
      expect(
        VoiceLocations.placeToSay(channelId: 'c1', connected: true, said: null),
        'c1',
      );
    });

    test('a move leaves the old channel at once', () {
      expect(
        VoiceLocations.placeToSay(
          channelId: 'c2',
          connected: false,
          said: 'c1',
        ),
        isNull,
      );
    });

    test('a rejoin of the same channel keeps it', () {
      // A region change or a dropped connection coming back: nobody's
      // sidebar folds us out and back in.
      expect(
        VoiceLocations.placeToSay(
          channelId: 'c1',
          connected: false,
          said: 'c1',
        ),
        'c1',
      );
    });

    test('out of a call says nowhere', () {
      expect(
        VoiceLocations.placeToSay(
          channelId: null,
          connected: false,
          said: 'c1',
        ),
        isNull,
      );
    });
  });
}
