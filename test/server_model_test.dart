import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/enums/channel_type.dart';

void main() {
  Server base() => Server(
        id: 'srv1',
        name: 'Test',
        supabaseUrl: 'http://localhost:8000',
        token: 'tok1',
        tokenIssuedAt: DateTime.now(),
      );

  group('Server token freshness', () {
    test('a freshly issued token is not near expiry', () {
      expect(base().isTokenNearExpiry, isFalse);
    });

    test('a token older than 50 minutes is near expiry', () {
      final s = base().copyWith(
        tokenIssuedAt: DateTime.now().subtract(const Duration(minutes: 51)),
      );
      expect(s.isTokenNearExpiry, isTrue);
    });

    test('copyWith stamps a fresh issue time when the token changes '
        '(prevents a perpetual-refresh loop)', () {
      final stale = base().copyWith(
        tokenIssuedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(stale.isTokenNearExpiry, isTrue);

      final refreshed = stale.copyWith(token: 'tok2');
      expect(refreshed.token, 'tok2');
      expect(refreshed.isTokenNearExpiry, isFalse); // re-stamped to now
    });

    test('copyWith without a token change keeps the existing issue time', () {
      final t = DateTime.now().subtract(const Duration(minutes: 51));
      final s = base().copyWith(tokenIssuedAt: t).copyWith(name: 'Renamed');
      expect(s.isTokenNearExpiry, isTrue); // issue time preserved
    });
  });

  group('Server JSON', () {
    test('round-trips through toJson/fromJson', () {
      final s = base().copyWith(channels: [
        const Channel(id: 'c1', name: 'general', channelType: ChannelType.text),
      ]);
      final restored = Server.fromJson(s.toJson());

      expect(restored.id, s.id);
      expect(restored.supabaseUrl, s.supabaseUrl);
      expect(restored.token, s.token);
      expect(restored.channels.single.name, 'general');
    });

    test('a persisted server without tokenIssuedAt is treated as stale', () {
      final json = base().toJson()..remove('tokenIssuedAt');
      expect(Server.fromJson(json).isTokenNearExpiry, isTrue);
    });
  });

  group('Channel JSON', () {
    test('round-trips with snake_case channel_type', () {
      const c = Channel(id: 'c1', name: 'voice-1', channelType: ChannelType.voice);
      final json = c.toJson();
      expect(json['channel_type'], 'voice');

      final restored = Channel.fromJson(json);
      expect(restored.id, 'c1');
      expect(restored.channelType, ChannelType.voice);
    });
  });
}
