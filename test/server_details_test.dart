import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_details.dart';
import 'package:rift/data/classes/server_limits.dart';

void main() {
  // The full shape `get_server_details()` returns (self-host 022, extended by
  // 028 and 029), trimmed to what the parser reads.
  Map<String, dynamic> reply() => {
    'server_id': 'srv1',
    'name': 'Cartography Club',
    'icon_url': 'https://example.test/icon.png',
    'livekit_url': 'ws://192.168.1.6:7880',
    'supabase_key': 'anon-key',
    'channels': <dynamic>[],
    'max_attachment_bytes': 26214400,
    'message_retention_days': 0,
    'message_history_cap': 0,
    'dm_retention_days': null,
    'dm_history_cap': null,
    'max_voice_participants': 1,
    'max_share_mbps': 4,
    'max_members': 5,
    'max_storage_bytes': 5242880,
    'storage_used': 1048576,
  };

  group('ServerDetails.fromJson', () {
    // The bug this file exists for: three paths asked for this reply and each
    // picked its own fields out by hand, so the limits reached only the one
    // that happened to name them and `storage_used` reached nobody at all
    // after joining. A client that cold-started held a screen-share cap of
    // "none" on a server that had set one, and an attachment pre-check that
    // measured against zero bytes used.
    test('carries every operator limit and the measured usage', () {
      final d = ServerDetails.fromJson(reply());

      expect(d.limits, isNotNull);
      expect(d.limits!.maxVoiceParticipants, 1);
      expect(d.limits!.maxShareMbps, 4);
      expect(d.limits!.maxMembers, 5);
      expect(d.limits!.maxStorageBytes, 5242880);
      expect(d.storageUsed, 1048576);
    });

    test('carries the server identity, not just its contents', () {
      final d = ServerDetails.fromJson(reply());

      expect(d.name, 'Cartography Club');
      expect(d.iconUrl, 'https://example.test/icon.png');
      expect(d.livekitUrl, 'ws://192.168.1.6:7880');
      expect(d.supabaseKey, 'anon-key');
      expect(d.channels, isEmpty);
    });

    // A banned member's reply is their own row and an empty channel list. It
    // mentions no limits, and `ServerLimits.fromJson` would happily invent a
    // full set of defaults from it — which `copyWith` would then apply,
    // wiping an operator's caps on the way past.
    test('a reply that mentions no limits leaves them alone', () {
      final d = ServerDetails.fromJson({
        'server_id': 'srv1',
        'user': null,
        'channels': <dynamic>[],
      });

      expect(d.limits, isNull);
      expect(d.storageUsed, isNull);
      expect(d.name, isNull);
      expect(d.livekitUrl, isNull);
    });

    // An older server has the 022 columns but not 028's or 029's. That reply
    // does carry limits, and the caps it does not mention are "no cap" —
    // which is the right answer for a server that cannot enforce them.
    test('a server too old for the newer caps reports them unlimited', () {
      final old = reply()
        ..remove('max_voice_participants')
        ..remove('max_share_mbps')
        ..remove('max_members')
        ..remove('max_storage_bytes')
        ..remove('storage_used');

      final d = ServerDetails.fromJson(old);

      expect(d.limits, isNotNull);
      expect(d.limits!.maxAttachmentBytes, 26214400);
      expect(d.limits!.maxVoiceParticipants, ServerLimits.unlimited);
      expect(d.limits!.maxShareMbps, ServerLimits.unlimited);
      expect(d.limits!.maxMembers, ServerLimits.unlimited);
      expect(d.limits!.maxStorageBytes, ServerLimits.unlimited);
      expect(d.storageUsed, isNull);
    });
  });
}
