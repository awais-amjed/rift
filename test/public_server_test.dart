import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/public_server.dart';
import 'package:rift/data/invite_link.dart';

/// The directory row and the tag rules the client enforces ahead of the
/// database. `ServerTags` mirrors a CHECK constraint in central migration 007,
/// so what these really pin is that the two still agree.
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

  group('ServerTags', () {
    test('accepts what the column accepts', () {
      expect(ServerTags.isValid('gaming'), isTrue);
      expect(ServerTags.isValid('board-games'), isTrue);
      expect(ServerTags.isValid('a1'), isTrue);
    });

    test('refuses what the column refuses', () {
      expect(ServerTags.isValid('a'), isFalse, reason: 'under two characters');
      expect(ServerTags.isValid('x' * 21), isFalse, reason: 'over twenty');
      expect(ServerTags.isValid('Gaming'), isFalse, reason: 'uppercase');
      expect(ServerTags.isValid('board games'), isFalse, reason: 'a space');
      expect(ServerTags.isValid('under_score'), isFalse);
    });

    test('normalises free text into one tag rather than dropping the gap', () {
      expect(ServerTags.normalise('  Board Games '), 'board-games');
      expect(ServerTags.normalise('Sci-Fi!'), 'sci-fi');
      expect(ServerTags.normalise('two__words'), 'two-words');
    });

    test('normalising returns null when nothing usable survives', () {
      expect(ServerTags.normalise('!!'), isNull);
      expect(ServerTags.normalise('a'), isNull);
      expect(ServerTags.normalise('   '), isNull);
    });
  });

  /// The editor turns typing into a chip on Enter, and a tag left in the box
  /// used to be invisible to the save — so filling the field and pressing Save
  /// published no tags at all. Saving reads through here instead.
  group('ServerTags.withPending', () {
    test('picks up a tag that was typed but never turned into a chip', () {
      expect(ServerTags.withPending(const ['gaming'], 'Board Games'), [
        'gaming',
        'board-games',
      ]);
    });

    test('an empty or unusable box changes nothing', () {
      expect(ServerTags.withPending(const ['gaming'], ''), ['gaming']);
      expect(ServerTags.withPending(const ['gaming'], '  '), ['gaming']);
      expect(ServerTags.withPending(const ['gaming'], '!!'), ['gaming']);
    });

    test('a duplicate is dropped rather than repeated', () {
      expect(ServerTags.withPending(const ['gaming'], 'Gaming'), ['gaming']);
    });

    test('it cannot push a listing past the column limit', () {
      final full = List.generate(ServerTags.maxCount, (i) => 'tag-$i');
      expect(ServerTags.withPending(full, 'one-more'), full);
    });

    test('no chips yet and one in the box still saves that one', () {
      expect(ServerTags.withPending(const [], 'tech'), ['tech']);
    });
  });
}
