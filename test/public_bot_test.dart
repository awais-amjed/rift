import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/public_bot.dart';

/// The bot directory row as the browser reads it, and the two things about it
/// that are easy to get wrong: the manifest is somebody else's JSON, and the
/// like is the only field that ever changes without the row being re-fetched.
void main() {
  Map<String, dynamic> row([Map<String, dynamic> overrides = const {}]) => {
    'id': 'bbbb0000-0000-4000-8000-000000000001',
    'owner_id': 'cccc0000-0000-4000-8000-000000000001',
    'name': 'Dicebot',
    'description': 'Rolls dice',
    'icon_url': null,
    'source_url': 'https://github.com/someone/dicebot',
    'tags': ['games', 'utility'],
    'manifest': {
      'data_use': 'Rolls are computed locally and nothing leaves the server.',
      'commands': [
        {'name': 'Roll', 'usage': '<dice>', 'description': 'Roll some dice'},
        {'name': 'stats'},
      ],
    },
    'is_listed': true,
    'like_count': 7,
    'created_at': '2026-08-12T10:00:00Z',
    'updated_at': '2026-09-01T10:00:00Z',
    ...overrides,
  };

  group('PublicBot.fromJson', () {
    test('reads a listing', () {
      final bot = PublicBot.fromJson(row());
      expect(bot.name, 'Dicebot');
      expect(bot.sourceUrl, 'https://github.com/someone/dicebot');
      expect(bot.tags, ['games', 'utility']);
      expect(bot.likeCount, 7);
      expect(bot.isListed, isTrue);
    });

    test('the source host is the provenance a row has space for', () {
      expect(PublicBot.fromJson(row()).sourceHost, 'github.com');
    });

    test('a malformed source is still a host of some kind, never a throw', () {
      // Central's CHECK means this should not arrive, but a listing is
      // somebody else's row and a browser that throws on one shows none.
      final bot = PublicBot.fromJson(row({'source_url': 'not a url'}));
      expect(bot.sourceHost, isNotEmpty);
    });

    test('the manifest comes through, lower-cased and typed', () {
      final manifest = PublicBot.fromJson(row()).manifest;
      expect(manifest.commands.map((c) => c.name), ['roll', 'stats']);
      expect(manifest.commands.first.usage, '<dice>');
      expect(manifest.dataUse, startsWith('Rolls are computed'));
    });

    test('a bot with no manifest renders as one with no commands', () {
      final bot = PublicBot.fromJson(row({'manifest': null}));
      expect(bot.manifest.commands, isEmpty);
      expect(bot.manifest.dataUse, isNull);
    });

    test('a like is the reader\'s, so it is never read from the row', () {
      // `liked_by_me` is not a column — it is answered per reader from
      // `bot_likes`. A row claiming one must not be believed.
      final bot = PublicBot.fromJson(row({'liked_by_me': true}));
      expect(bot.likedByMe, isFalse);
      expect(PublicBot.fromJson(row(), likedByMe: true).likedByMe, isTrue);
    });

    test('missing counts and flags fall back rather than throwing', () {
      final bot = PublicBot.fromJson(
        row({'like_count': null, 'is_listed': null, 'tags': null}),
      );
      expect(bot.likeCount, 0);
      expect(bot.isListed, isTrue);
      expect(bot.tags, isEmpty);
    });
  });

  group('PublicBot.copyWith', () {
    test('moves the heart and the count together', () {
      final liked = PublicBot.fromJson(
        row(),
      ).copyWith(likedByMe: true, likeCount: 8);
      expect(liked.likedByMe, isTrue);
      expect(liked.likeCount, 8);
    });

    test('a count central did not answer with leaves the old one alone', () {
      // `setLiked` answers null when the like was already there — a second
      // tap, or two devices. The row must not fall back to zero.
      final same = PublicBot.fromJson(row()).copyWith(likedByMe: true);
      expect(same.likeCount, 7);
    });

    test('changes nothing else', () {
      final before = PublicBot.fromJson(row());
      final after = before.copyWith(likedByMe: true);
      expect(after.id, before.id);
      expect(after.name, before.name);
      expect(after.sourceUrl, before.sourceUrl);
      expect(after.tags, before.tags);
      expect(after.manifest.commands.length, before.manifest.commands.length);
      expect(after.createdAt, before.createdAt);
    });
  });

  group('BotSort', () {
    test('names the column central orders on', () {
      // Mirrors idx_public_bots_top and idx_public_bots_new. If either index
      // is renamed away from its column, the order silently stops using it.
      expect(BotSort.top.column, 'like_count');
      expect(BotSort.fresh.column, 'created_at');
    });
  });
}
