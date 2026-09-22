import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/participant_setting.dart';
import 'package:rift/data/classes/resolved_invite.dart';
import 'package:rift/data/classes/webhook.dart';

/// Models too small for a file of their own, parsed the way the server and
/// the persisted state hand them over.
void main() {
  group('Webhook.fromJson', () {
    Map<String, dynamic> row({Object? lastUsed}) => {
      'id': 'w',
      'channel_id': 'c',
      'name': 'CI',
      'created_at': '2026-09-01T10:00:00Z',
      'last_used_at': lastUsed,
    };

    test('a webhook that never posted has no last use', () {
      // The field is interpolated before parsing, so null arrives as "null".
      expect(Webhook.fromJson(row()).lastUsedAt, isNull);
    });

    test('reads the last use when there is one', () {
      final hook = Webhook.fromJson(row(lastUsed: '2026-09-02T08:30:00Z'));
      expect(hook.lastUsedAt, DateTime.utc(2026, 9, 2, 8, 30));
      expect(hook.channelId, 'c');
    });
  });

  group('ParticipantSetting', () {
    test('an empty entry is unmuted at full volume', () {
      final s = ParticipantSetting.fromJson(const {});
      expect(s.muted, isFalse);
      expect(s.volume, 1.0);
    });

    test('survives a round trip, with an integer volume', () {
      final s = ParticipantSetting.fromJson(const {'muted': true, 'volume': 0});
      expect(s.volume, 0.0);
      final back = ParticipantSetting.fromJson(s.toJson());
      expect(back.muted, isTrue);
      expect(back.volume, 0.0);
    });
  });

  group('ResolvedInvite.host', () {
    ResolvedInvite at(String url) => ResolvedInvite(
      serverUrl: url,
      inviteCode: 'i',
      serverId: 's',
      serverName: 'n',
    );

    test('shows the host alone', () {
      expect(at('https://chat.example.org:8443/x').host, 'chat.example.org');
    });

    test('falls back to the raw address when it does not parse', () {
      expect(at('http://[bad').host, 'http://[bad');
    });
  });
}
