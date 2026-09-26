import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/public_bot.dart';
import 'package:rift/data/classes/public_server.dart';
import 'package:rift/data/enums/listing_kind.dart';
import 'package:rift/data/enums/report_reason.dart';

void main() {
  group('ReportReason', () {
    test('round-trips every value', () {
      for (final reason in ReportReason.values) {
        expect(ReportReason.fromString(reason.toJson()), reason);
      }
    });

    test('reads a reason it does not know as other', () {
      expect(ReportReason.fromString('added_later'), ReportReason.other);
    });
  });

  test('ListingKind reads bot and server', () {
    expect(ListingKind.fromString('bot'), ListingKind.bot);
    expect(ListingKind.fromString('server'), ListingKind.server);
  });

  group('hidden listings', () {
    test('a server listing carries its moderator note', () {
      final server = PublicServer.fromJson({
        'id': 's',
        'owner_id': 'u',
        'supabase_url': 'https://a.example.com',
        'server_id': 'x',
        'invite_code': 'code',
        'name': 'A',
        'updated_at': '2026-09-26T10:00:00Z',
        'hidden_at': '2026-09-26T11:00:00Z',
        'hidden_reason': 'Hateful name',
      });
      expect(server.isHidden, isTrue);
      expect(server.hiddenReason, 'Hateful name');
      expect(PublicServer.fromJson(server.toJson()).isHidden, isTrue);
    });

    test('a bot listing keeps it through a like', () {
      final bot = PublicBot.fromJson({
        'id': 'b',
        'owner_id': 'u',
        'name': 'bot',
        'source_url': 'https://example.com/bot',
        'created_at': '2026-09-26T10:00:00Z',
        'updated_at': '2026-09-26T10:00:00Z',
        'hidden_at': '2026-09-26T11:00:00Z',
      });
      expect(bot.copyWith(likedByMe: true).isHidden, isTrue);
    });

    test('a listing central says nothing about is not hidden', () {
      final bot = PublicBot.fromJson({
        'id': 'b',
        'owner_id': 'u',
        'name': 'bot',
        'source_url': 'https://example.com/bot',
      });
      expect(bot.isHidden, isFalse);
    });
  });
}
