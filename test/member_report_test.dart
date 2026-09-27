import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/member_report.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/dm_policy.dart';
import 'package:rift/data/enums/member_report_reason.dart';
import 'package:rift/data/enums/report_outcome.dart';
import 'package:rift/data/enums/server_permission.dart';

/// A `reports` row as a reviewer reads it — the shape `listReports` selects,
/// people and channel embedded.
void main() {
  Map<String, dynamic> row({Map<String, dynamic> overrides = const {}}) => {
    'id': 7,
    'created_at': '2026-09-27T10:00:00Z',
    'server_id': 's',
    'reporter_id': 'r',
    'target_id': 't',
    'reason': 'harassment',
    'note': 'in DMs',
    'message_id': 9800,
    'channel_id': 'c',
    'message_created_at': '2026-09-27T09:59:00Z',
    'origin_name': null,
    'ciphertext': 'sealed',
    'nonce': 'n',
    'signature': 's',
    'key_version': 3,
    'outcome': null,
    'resolved_by': null,
    'resolved_at': null,
    'reporter': {'display_name': 'Rae', 'username': 'rae'},
    'target': {
      'display_name': 'Tom',
      'username': 'tom',
      'public_key': 'pk',
      'is_banned': false,
      'timed_out_until': null,
    },
    'channel': {'name': 'general'},
    ...overrides,
  };

  test('a message report carries the envelope, the people and the channel', () {
    final report = MemberReport.fromJson(row());
    expect(report.reason, MemberReportReason.harassment);
    expect(report.isOpen, isTrue);
    expect(report.message!.ciphertext, 'sealed');
    expect(report.message!.keyVersion, 3);
    expect(report.message!.channelId, 'c');
    expect(report.target!.publicKey, 'pk');
    expect(report.reporter!.displayName, 'Rae');
    expect(report.channelName, 'general');
  });

  test('a member report has no message, and a closed one its outcome', () {
    final report = MemberReport.fromJson(
      row(
        overrides: {
          'message_id': null,
          'channel_id': null,
          'ciphertext': null,
          'key_version': null,
          'message_created_at': null,
          'outcome': 'timed_out',
          'resolved_at': '2026-09-27T11:00:00Z',
          'channel': null,
        },
      ),
    );
    expect(report.message, isNull);
    expect(report.outcome, ReportOutcome.timedOut);
    expect(report.isOpen, isFalse);
    expect(report.channelName, isNull);
  });

  test('a private channel the reviewer cannot see comes back unnamed', () {
    expect(
      MemberReport.fromJson(row(overrides: {'channel': null})).channelName,
      isNull,
    );
  });

  test('the outcome survives the round trip through its wire name', () {
    for (final outcome in ReportOutcome.values) {
      expect(ReportOutcome.fromString(outcome.toJson()), outcome);
    }
    expect(ReportOutcome.timedOut.toJson(), 'timed_out');
  });

  test('a member row reads the DM setting and the time-out', () {
    final member = ServerMember.fromJson({
      'id': 'u',
      'username': 'u',
      'display_name': 'U',
      'dm_policy': 'requests',
      'timed_out_until': DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    });
    expect(member.dmPolicy, DmPolicy.requests);
    expect(member.isTimedOut, isTrue);
    final lifted = member.copyWith(clearTimedOut: true);
    expect(lifted.isTimedOut, isFalse);
  });

  test('Review reports is bit 28, and administrators hold it', () {
    expect(ServerPermission.reviewReports.bit, 28);
    const admin = UserPermissions(bits: 1);
    expect(admin.can(ServerPermission.reviewReports), isTrue);
    const plain = UserPermissions(bits: 1 << 10);
    expect(plain.can(ServerPermission.reviewReports), isFalse);
  });
}
