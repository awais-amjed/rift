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
}
