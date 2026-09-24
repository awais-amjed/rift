import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/livekit_node.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/repositories/voice_region_probe.dart';
import 'package:rift/logic/services/voice_signal.dart';

void main() {
  group('LiveKitNode', () {
    test('round-trips through JSON', () {
      const node = LiveKitNode(
        id: 'n1',
        label: 'Singapore',
        url: 'wss://sg.example.com',
        isDefault: true,
      );
      expect(LiveKitNode.fromJson(node.toJson()), node);
    });

    test('a server that sends only an id still parses', () {
      // An older or partial payload must not throw — a missing label is an
      // unnamed region, not a broken server.
      final node = LiveKitNode.fromJson({'id': 'n1'});
      expect(node.id, 'n1');
      expect(node.label, '');
      expect(node.isDefault, isFalse);
    });
  });

  group('Channel voice fields', () {
    test('carries the pin and where a call is, and round-trips them', () {
      const channel = Channel(
        id: 'c1',
        name: 'General',
        channelType: ChannelType.voice,
        livekitNodeId: 'n1',
        voiceNodeId: 'n2',
      );
      final parsed = Channel.fromJson(channel.toJson());
      expect(parsed.livekitNodeId, 'n1');
      expect(parsed.voiceNodeId, 'n2');
    });

    test('both are null when the server does not mention them', () {
      final channel = Channel.fromJson({
        'id': 'c1',
        'name': 'General',
        'channel_type': 'voice',
      });
      // Null is "automatic" and "nobody in it" — which is what a server with
      // one region answers, and must not read as an error.
      expect(channel.livekitNodeId, isNull);
      expect(channel.voiceNodeId, isNull);
    });
  });

  group('the default region\'s title', () {
    // The row appends "(default)" so the one that cannot be removed says why.
    // A server nobody has renamed calls that node "Default", and appending
    // to it produced "Default (default)" — seen on the real settings page.
    String title(LiveKitNode n) {
      if (!n.isDefault) return n.label;
      if (n.label.trim().toLowerCase() == 'default') return n.label;
      return '${n.label} (default)';
    }

    test('does not repeat itself when the label already says it', () {
      expect(
        title(const LiveKitNode(id: 'n', label: 'Default', url: 'ws://h', isDefault: true)),
        'Default',
      );
    });

    test('marks a renamed default', () {
      expect(
        title(const LiveKitNode(id: 'n', label: 'Frankfurt', url: 'ws://h', isDefault: true)),
        'Frankfurt (default)',
      );
    });

    test('says nothing extra about an ordinary region', () {
      expect(
        title(const LiveKitNode(id: 'n', label: 'Singapore', url: 'ws://h')),
        'Singapore',
      );
    });
  });

  group('the rejoin signal', () {
    List<int> packet(Map<String, Object?> body) => utf8.encode(jsonEncode(body));

    test('is obeyed when the server sent it', () {
      expect(
        VoiceSignal.isRejoin(
          data: packet({'v': 1, 'type': 'rejoin', 'channel_id': 'c1'}),
          topic: VoiceSignal.moveTopic,
          fromServer: true,
        ),
        isTrue,
      );
    });

    test('is refused from a member', () {
      // A packet with a sender is another person in the room talking, and a
      // member cannot move everybody else's call.
      expect(
        VoiceSignal.isRejoin(
          data: packet({'v': 1, 'type': 'rejoin', 'channel_id': 'c1'}),
          topic: VoiceSignal.moveTopic,
          fromServer: false,
        ),
        isFalse,
      );
    });

    test('is not confused with a move between channels', () {
      final move = packet({'v': 1, 'type': 'move', 'channel_id': 'c2'});
      expect(
        VoiceSignal.isRejoin(
          data: move,
          topic: VoiceSignal.moveTopic,
          fromServer: true,
        ),
        isFalse,
      );
      // And the other way round, or a moved call would drag people into a
      // channel they were not in.
      final rejoin = packet({'v': 1, 'type': 'rejoin', 'channel_id': 'c1'});
      expect(
        VoiceSignal.moveDestination(
          data: rejoin,
          topic: VoiceSignal.moveTopic,
          fromServer: true,
        ),
        isNull,
      );
    });

    test('ignores a version it does not know', () {
      expect(
        VoiceSignal.isRejoin(
          data: packet({'v': 99, 'type': 'rejoin', 'channel_id': 'c1'}),
          topic: VoiceSignal.moveTopic,
          fromServer: true,
        ),
        isFalse,
      );
    });

    test('survives rubbish on the data channel', () {
      expect(
        VoiceSignal.isRejoin(
          data: const [1, 2, 3],
          topic: VoiceSignal.moveTopic,
          fromServer: true,
        ),
        isFalse,
      );
    });
  });

  group('VoiceRegionProbe.httpUrlFor', () {
    test('swaps the WebSocket scheme for its HTTP one', () {
      expect(
        VoiceRegionProbe.httpUrlFor('wss://sg.example.com').toString(),
        'https://sg.example.com/',
      );
      expect(
        VoiceRegionProbe.httpUrlFor('ws://192.168.1.6:7880').toString(),
        'http://192.168.1.6:7880/',
      );
    });

    test('drops any path, because the probe asks for the root', () {
      expect(
        VoiceRegionProbe.httpUrlFor('wss://example.com/live').toString(),
        'https://example.com/',
      );
    });

    test('answers null for something that is not an address', () {
      expect(VoiceRegionProbe.httpUrlFor(''), isNull);
      expect(VoiceRegionProbe.httpUrlFor('not a url'), isNull);
    });
  });
}
