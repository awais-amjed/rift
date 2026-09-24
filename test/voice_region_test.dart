import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/livekit_node.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/repositories/voice_region_probe.dart';

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
