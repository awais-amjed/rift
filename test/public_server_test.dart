import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/public_server.dart';
import 'package:rift/data/invite_link.dart';

/// The server directory row as the browser reads it. The tag rules it used to
/// carry moved out with `DirectoryTags`, which both directories now share.
void main() {
  Map<String, dynamic> row([Map<String, dynamic> overrides = const {}]) => {
    'id': 'ffff0000-0000-4000-8000-000000000001',
    'owner_id': 'cccc0000-0000-4000-8000-000000000001',
    'supabase_url': 'https://alpha.supabase.co',
    'server_id': 'aaaa0000-0000-4000-8000-000000000001',
    'invite_code': 'abc123xyz9',
    'name': 'Alpha',
    'description': 'A place',
    'icon_url': null,
    'tags': ['gaming', 'tech'],
    'member_count': 12,
    'is_listed': true,
    'updated_at': '2026-08-12T10:00:00Z',
    ...overrides,
  };

  group('PublicServer.fromJson', () {
    test('round-trips a listing', () {
      final server = PublicServer.fromJson(row());
      final back = PublicServer.fromJson(server.toJson());

      expect(back.id, server.id);
      expect(back.supabaseUrl, 'https://alpha.supabase.co');
      expect(back.serverId, 'aaaa0000-0000-4000-8000-000000000001');
      expect(back.inviteCode, 'abc123xyz9');
      expect(back.tags, ['gaming', 'tech']);
      expect(back.memberCount, 12);
      expect(back.isListed, isTrue);
      expect(back.updatedAt.toUtc(), DateTime.utc(2026, 8, 12, 10));
    });

    test('a row with no tags is an empty list, not null', () {
      final server = PublicServer.fromJson(row({'tags': null}));
      expect(server.tags, isEmpty);
    });

    test('the invite link is the same string the invite dialog produces', () {
      final server = PublicServer.fromJson(row());
      final parsed = InviteLink.parse(server.inviteLink);

      expect(parsed, isNotNull);
      expect(parsed!.serverUrl, 'https://alpha.supabase.co');
      expect(parsed.inviteCode, 'abc123xyz9');
    });

    test('the host is what a browser row shows for provenance', () {
      expect(PublicServer.fromJson(row()).host, 'alpha.supabase.co');
    });
  });
}
