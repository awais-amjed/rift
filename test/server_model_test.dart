import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_limits.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/enums/channel_type.dart';

void main() {
  Server base() => Server(
    id: 'srv1',
    name: 'Test',
    supabaseUrl: 'http://localhost:8000',
    token: 'tok1',
    tokenIssuedAt: DateTime.now(),
  );

  group('Server.copyWith as a partial update', () {
    // What `refreshServerDetails` relies on: it hands over whatever the server
    // reply contained and nothing else, so every field it omits has to survive
    // untouched. Before it passed `name`, a rename by another admin reached
    // only the client that made it — everyone else kept the old one until they
    // rejoined, and nothing looked wrong.
    Server full() => Server(
      id: 'srv1',
      name: 'Cartography Club',
      iconUrl: 'https://example.test/icon.png',
      supabaseUrl: 'http://localhost:8000',
      supabaseKey: 'anon-key',
      livekitUrl: 'ws://192.168.1.6:7880',
      token: 'tok1',
      tokenIssuedAt: DateTime.now(),
      channels: const [],
    );

    test('an all-null update changes nothing', () {
      final before = full();
      final after = before.copyWith();

      expect(after.name, before.name);
      expect(after.iconUrl, before.iconUrl);
      expect(after.supabaseKey, before.supabaseKey);
      expect(after.livekitUrl, before.livekitUrl);
      expect(after.token, before.token);
    });

    test('renaming leaves the rest of the server alone', () {
      final after = full().copyWith(name: 'Weekend Crew');

      expect(after.name, 'Weekend Crew');
      expect(after.livekitUrl, 'ws://192.168.1.6:7880');
      expect(after.supabaseKey, 'anon-key');
      expect(after.iconUrl, 'https://example.test/icon.png');
    });

    test('a reply that omits the name does not blank it', () {
      // The banned-member path returns a user row and no server identity at
      // all. Passing those nulls through must not erase what we already knew.
      final after = full().copyWith(name: null, iconUrl: null, limits: null);

      expect(after.name, 'Cartography Club');
      expect(after.iconUrl, 'https://example.test/icon.png');
      expect(after.limits, isNotNull);
    });
  });

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
      final s = base().copyWith(
        channels: [
          const Channel(
            id: 'c1',
            name: 'general',
            channelType: ChannelType.text,
          ),
        ],
      );
      final restored = Server.fromJson(s.toJson());

      expect(restored.id, s.id);
      expect(restored.supabaseUrl, s.supabaseUrl);
      expect(restored.token, s.token);
      expect(restored.channels.single.name, 'general');
    });

    // A server saved before the ceiling existed reads as the 50 MB storage
    // enforced then, never as "no ceiling".
    test('keeps the file ceiling, and an old save reads as 50 MB', () {
      final s = base().copyWith(maxFileBytes: 1073741824);
      expect(Server.fromJson(s.toJson()).maxFileBytes, 1073741824);
      final old = s.toJson()..remove('maxFileBytes');
      expect(Server.fromJson(old).maxFileBytes, ServerLimits.legacyFileCeiling);
    });

    test('a persisted server without tokenIssuedAt is treated as stale', () {
      final json = base().toJson()..remove('tokenIssuedAt');
      expect(Server.fromJson(json).isTokenNearExpiry, isTrue);
    });
  });

  group('Channel JSON', () {
    test('round-trips with snake_case channel_type', () {
      const c = Channel(
        id: 'c1',
        name: 'voice-1',
        channelType: ChannelType.voice,
      );
      final json = c.toJson();
      expect(json['channel_type'], 'voice');

      final restored = Channel.fromJson(json);
      expect(restored.id, 'c1');
      expect(restored.channelType, ChannelType.voice);
    });
  });

  // F-3: a kick is a ban an invite lifts, and both sides have to tell the
  // two apart — the kicked person's notice, and a moderator's list.
  group('Kicked', () {
    const row = {
      'id': 'u1',
      'username': 'kim',
      'display_name': 'Kim',
      'is_banned': true,
      'is_kicked': true,
    };

    test('our own row says the ban is a kick, and is not persisted', () {
      final me = ServerUser.fromJson(row);
      expect(me.isBanned, isTrue);
      expect(me.isKicked, isTrue);
      expect(me.toJson().containsKey('is_kicked'), isFalse);
      expect(ServerUser.fromJson(me.toJson()).isKicked, isFalse);
    });

    test('a member row carries it, and a ban clears it', () {
      final member = ServerMember.fromJson(row);
      expect(member.isKicked, isTrue);
      expect(member.copyWith(isMuted: true).isKicked, isTrue);
      expect(member.copyWith(isKicked: false).isKicked, isFalse);
    });

    test('an older server that sends no flag means banned', () {
      final member = ServerMember.fromJson({...row}..remove('is_kicked'));
      expect(member.isBanned, isTrue);
      expect(member.isKicked, isFalse);
    });
  });
}
