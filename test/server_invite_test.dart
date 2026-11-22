import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_invite.dart';
import 'package:rift/presentation/screens/home/servers/manage/panels/invites/invite_list_row.dart';

/// A row of the Invites page, as the server sends it.
void main() {
  Map<String, dynamic> row({Object? creator, String? expires}) => {
    'id': 'i1',
    'code': 'abcdefgh1234',
    'created_at': '2026-11-22T10:00:00Z',
    'created_by': creator == null ? null : 'u1',
    'max_uses': 5,
    'uses': 2,
    'expires_at': expires,
    'is_bot': false,
    'role_id': 'r1',
    'creator': creator,
  };

  test('reads who made it, by display name before username', () {
    final invite = ServerInvite.fromJson(
      row(creator: {'display_name': 'Ana', 'username': 'ana'}),
    );
    expect(invite.creatorName, 'Ana');
    expect(invite.maxUses, 5);
    expect(invite.uses, 2);
    expect(invite.roleId, 'r1');

    final unnamed = ServerInvite.fromJson(
      row(creator: {'display_name': ' ', 'username': 'ana'}),
    );
    expect(unnamed.creatorName, 'ana');
  });

  test('a link whose maker has gone has no creator', () {
    final invite = ServerInvite.fromJson(row());
    expect(invite.createdBy, isNull);
    expect(invite.creatorName, isNull);
  });

  test('shows only the end of the code', () {
    final invite = ServerInvite.fromJson(row());
    expect(invite.codeTail, '…1234');
    expect(invite.codeTail, isNot(contains('abcd')));
  });

  test('a link past its time is expired, one without a time never is', () {
    final now = DateTime.utc(2026, 11, 22, 12);
    expect(
      ServerInvite.fromJson(
        row(expires: '2026-11-22T11:00:00Z'),
      ).expiredAt(now),
      isTrue,
    );
    expect(
      ServerInvite.fromJson(
        row(expires: '2026-11-23T11:00:00Z'),
      ).expiredAt(now),
      isFalse,
    );
    expect(ServerInvite.fromJson(row()).expiredAt(now), isFalse);
  });

  test('the time left is rounded up, so a fresh 7-day link says 7d', () {
    final now = DateTime.utc(2026, 11, 22, 12);
    String left(Duration d) => InviteListRow.expiryText(now.add(d), now);
    expect(
      left(const Duration(days: 7) - const Duration(seconds: 5)),
      'Expires in 7d',
    );
    expect(left(const Duration(hours: 23, minutes: 30)), 'Expires in 1d');
    expect(left(const Duration(hours: 2, minutes: 10)), 'Expires in 3h');
    expect(left(const Duration(minutes: 59, seconds: 1)), 'Expires in 1h');
    expect(left(const Duration(seconds: 20)), 'Expires in 1m');
    expect(InviteListRow.expiryText(null, now), 'Never expires');
    expect(left(-const Duration(seconds: 1)), 'Expired');
  });
}
