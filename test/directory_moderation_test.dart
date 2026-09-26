import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/moderation_case.dart';
import 'package:rift/data/classes/public_bot.dart';
import 'package:rift/data/classes/public_server.dart';
import 'package:rift/data/enums/listing_kind.dart';
import 'package:rift/data/enums/report_reason.dart';

/// One queue entry the way central's `moderation_queue()` shapes it.
Map<String, dynamic> _case({
  String name = 'Bad Place',
  String? description = 'now clean',
  String reportedName = 'Bad Place',
  String? reportedDescription = 'now clean',
}) => {
  'listing': {
    'kind': 'server',
    'id': 'l1',
    'name': name,
    'description': description,
    'icon_path': null,
    'address': 'https://mod.example.com',
    'is_listed': true,
    'hidden_at': null,
    'hidden_reason': null,
    'owner_id': 'u1',
    'owner_handle': 'alice',
    'owner_banned': false,
  },
  'report_count': 2,
  'reports': [
    {
      'id': 'r2',
      'created_at': '2026-09-26T10:00:00Z',
      'reason': 'spam',
      'details': null,
      'reporter_handle': 'carol',
      'snapshot': {'name': name, 'description': description},
    },
    {
      'id': 'r1',
      'created_at': '2026-09-25T10:00:00Z',
      'reason': 'hate',
      'details': 'the name',
      'reporter_handle': 'bob',
      'snapshot': {'name': reportedName, 'description': reportedDescription},
    },
  ],
};

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

  group('ModerationCase', () {
    test('parses the listing and its reports', () {
      final item = ModerationCase.fromJson(_case());
      expect(item.listing.kind, ListingKind.server);
      expect(item.listing.ownerHandle, 'alice');
      expect(item.listing.host, 'mod.example.com');
      expect(item.reports.map((r) => r.reason), [
        ReportReason.spam,
        ReportReason.hate,
      ]);
      expect(item.reports.last.details, 'the name');
    });

    test('is not edited when it still says what was reported', () {
      expect(ModerationCase.fromJson(_case()).editedSinceReport, isFalse);
    });

    test('is edited when the first report saw something else', () {
      final item = ModerationCase.fromJson(
        _case(reportedName: 'Hateful Place', reportedDescription: 'slurs'),
      );
      expect(item.editedSinceReport, isTrue);
    });

    test('a missing description matches an empty one', () {
      final item = ModerationCase.fromJson(
        _case(description: null, reportedDescription: ''),
      );
      expect(item.editedSinceReport, isFalse);
    });
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
