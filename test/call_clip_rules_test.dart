import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/call_clip/clip_notice_rules.dart';
import 'package:rift/logic/services/call_clip/clip_signal.dart';
import 'package:rift/logic/services/voice_attributes.dart';

/// What the call is told about clipping, and how often.
///
/// The notices are the whole of the consent story: nobody can stop a clip,
/// so being told is what they get. A notice that never shows hides a
/// recording; one that shows on every rejoin is spam people learn to ignore.
/// The notice decoder runs on bytes off the data channel.
void main() {
  List<int> packet(Object? body) => utf8.encode(jsonEncode(body));

  group('ClipSignal', () {
    // The server's notice (`note_clip`), as it sends it.
    Map<String, Object?> notice({
      Object? v = 2,
      Object? type = 'clipped',
      Object? identity = 'user-a~pc',
      Object? seconds = 60,
    }) => {'v': v, 'type': type, 'identity': identity, 'seconds': seconds};

    ({String identity, int seconds})? read(
      Object? body, {
      String? topic,
      bool fromServer = true,
    }) => ClipSignal.read(
      data: body is List<int> ? body : packet(body),
      topic: topic ?? ClipSignal.topic,
      fromServer: fromServer,
    );

    test('the server\'s notice names the connection and the length', () {
      expect(read(notice()), (identity: 'user-a~pc', seconds: 60));
    });

    test('a member\'s own packet is not believed', () {
      // Anybody with the data right can send one, and before 1.9.0 the
      // clipper did; only the server checks the clipper is in the call.
      expect(read(notice(), fromServer: false), isNull);
      expect(read({'v': 1, 'type': 'clipped', 'seconds': 60}), isNull);
    });

    test('another topic is not a clip', () {
      expect(read(notice(), topic: 'rift.sound'), isNull);
    });

    test('an unknown version or type is ignored', () {
      expect(read(notice(v: 3)), isNull);
      expect(read(notice(type: 'sound')), isNull);
    });

    test('garbage is ignored', () {
      expect(read(<int>[0xff, 0x00, 0x12]), isNull);
      expect(read([1, 2, 3]), isNull);
      expect(read(notice(seconds: 'x')), isNull);
      expect(read(notice(identity: '')), isNull);
      expect(read(notice(identity: 7)), isNull);
    });

    test('the length is held to 1..120 seconds', () {
      expect(read(notice(seconds: 0))?.seconds, 1);
      expect(read(notice(seconds: 500))?.seconds, 120);
    });
  });

  group('ClipNoticeRules', () {
    test('someone is told about once per call', () {
      final rules = ClipNoticeRules();
      expect(rules.newlyClipping(['a', 'b'], selfId: 'me'), ['a', 'b']);
      expect(rules.newlyClipping(['a', 'b', 'c'], selfId: 'me'), ['c']);
      expect(rules.newlyClipping(['a'], selfId: 'me'), isEmpty);
    });

    test('you are never told about yourself', () {
      final rules = ClipNoticeRules();
      expect(rules.newlyClipping(['me', 'a'], selfId: 'me'), ['a']);
      expect(rules.newlyClipping(['me'], selfId: 'me'), isEmpty);
    });

    test('a new call tells again', () {
      final rules = ClipNoticeRules();
      rules.newlyClipping(['a'], selfId: 'me');
      rules.reset();
      expect(rules.newlyClipping(['a'], selfId: 'me'), ['a']);
    });

    test('a clip is told at most once a minute per person', () {
      final rules = ClipNoticeRules();
      final t0 = DateTime(2026, 11, 21, 12);
      expect(rules.admitClip('a', t0), isTrue);
      expect(
        rules.admitClip('a', t0.add(const Duration(seconds: 59))),
        isFalse,
      );
      expect(rules.admitClip('b', t0.add(const Duration(seconds: 1))), isTrue);
      expect(rules.admitClip('a', t0.add(const Duration(seconds: 60))), isTrue);
    });
  });

  group('the words', () {
    test('who has clipping on', () {
      expect(clippingOnText(['Sam']), 'Sam has clipping on');
      expect(clippingOnText(['Sam', 'Alex']), 'Sam and Alex have clipping on');
      expect(
        clippingOnText(['Sam', 'Alex', 'Kim']),
        'Sam, Alex and 1 other have clipping on',
      );
      expect(
        clippingOnText(['Sam', 'Alex', 'Kim', 'Lee']),
        'Sam, Alex and 2 others have clipping on',
      );
    });

    test('what was clipped', () {
      expect(clippedText('Sam', 60), 'Sam clipped the last minute');
      expect(clippedText('Sam', 120), 'Sam clipped the last 2 minutes');
      expect(clippedText('Sam', 30), 'Sam clipped the last 30 seconds');
      expect(clippedText('Sam', 1), 'Sam clipped the last second');
    });
  });

  group('VoiceAttributes clipping', () {
    test('published and read back', () {
      final attrs = VoiceAttributes.forSelf(
        deafened: false,
        watching: const {},
        pushToTalkIdle: false,
        plays: const {},
        clipping: true,
      );
      expect(attrs[VoiceAttributes.clippingKey], 'true');
      expect(VoiceAttributes.isClipping(attrs), isTrue);
    });

    test('absent reads as off', () {
      expect(VoiceAttributes.isClipping(const {}), isFalse);
    });
  });
}
