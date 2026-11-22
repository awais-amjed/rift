import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_invite.dart';

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
}
