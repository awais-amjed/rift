import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/audio_reception.dart';

/// Audio this client should not hear is held, never unsubscribed.
///
/// Unsubscribing gave the track's slot on the connection back to LiveKit's
/// server, which handed it to the next track; subscribing to the first track
/// again opened a second slot under the same id, and the frame cryptor went
/// on the wrong one. The other played its frames still encrypted — static on
/// the stream and on every voice routed through it, until the call was joined
/// again (reported Oct 19 2026 after watching a stream).
void main() {
  group('hearsRemoteAudio', () {
    bool hears({
      bool deafened = false,
      bool stream = false,
      bool watched = false,
      bool ownerless = false,
      bool someoneElse = false,
      bool playedElsewhere = false,
    }) => hearsRemoteAudio(
      deafened: deafened,
      stream: stream,
      watched: watched,
      ownerless: ownerless,
      someoneElse: someoneElse,
      playedElsewhere: playedElsewhere,
    );

    test('a voice is heard unless deafened', () {
      expect(hears(), isTrue);
      expect(hears(deafened: true), isFalse);
    });

    test("a stream's sound only while it is watched", () {
      expect(hears(stream: true), isFalse);
      expect(hears(stream: true, watched: true), isTrue);
      expect(hears(stream: true, watched: true, deafened: true), isFalse);
    });

    test('a share whose owner has left is not heard, watched or not', () {
      expect(hears(ownerless: true), isFalse);
      expect(hears(stream: true, watched: true, ownerless: true), isFalse);
    });

    test('a stream the watch connection plays is held in the call', () {
      expect(
        hears(stream: true, watched: true, playedElsewhere: true),
        isFalse,
      );
    });

    test('listening only to one person holds everyone else, streams too', () {
      expect(hears(someoneElse: true), isFalse);
      expect(hears(stream: true, watched: true, someoneElse: true), isFalse);
    });
  });

  test('receivers sharing an id are found, once each', () {
    expect(sharedReceiverIds(['TR_a', 'TR_b', 'TR_c']), isEmpty);
    expect(sharedReceiverIds(['TR_a', 'TR_b', 'TR_a', 'TR_a']), {'TR_a'});
  });

  test('the call unsubscribes only from its own share', () {
    // Every `unsubscribe()` left in the call has to say, just above it, that
    // it is this client's own share, which is dropped for good. Subscribing
    // to anything else again puts its frame cryptor on the wrong receiver, so
    // audio and pictures both go through `disable()` (`_AudioReceptionMixin`,
    // `_PicturePauseMixin`).
    final allowed = RegExp(r'_isOwnShare');
    final offenders = <String>[];
    for (final file in Directory('lib/logic/cubits/livekit').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!line.contains('.unsubscribe()')) continue;
        final context = lines.sublist(i < 5 ? 0 : i - 5, i + 1).join('\n');
        if (!allowed.hasMatch(context)) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
