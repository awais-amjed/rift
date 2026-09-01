import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/repositories/server_user_row.dart';

/// Reshaping a `users` row into what the client models read.
///
/// The reason this is worth testing at all is that it is only ever wrong in one
/// field, and one field is invisible: a dropped `is_bot` is a bot that renders
/// as a person, a dropped `manifest` is a bot that claims nothing. Neither
/// looks like a bug from inside the repository.
void main() {
  Map<String, dynamic> row({Map<String, dynamic> overrides = const {}}) => {
    'id': 'u1',
    'username': 'sam',
    'display_name': 'Sam',
    'avatar_path': 'a.png',
    'chat_public_key': 'k',
    'is_muted': false,
    'is_deafened': false,
    'is_banned': false,
    'is_bot': true,
    'manifest': {'commands': []},
    'is_server_admin': true,
    'is_channel_manager': false,
    'can_create_tokens': true,
    // Whatever else the select happened to bring back.
    'created_at': 'yesterday',
    ...overrides,
  };

  group('flattening a row', () {
    test('carries every field the client models read', () {
      final out = ServerUserRow.of(row());
      for (final key in [
        'id',
        'username',
        'display_name',
        'avatar_path',
        'chat_public_key',
        'is_muted',
        'is_deafened',
        'is_banned',
        'is_bot',
        'manifest',
      ]) {
        expect(out.containsKey(key), isTrue, reason: '$key was dropped');
      }
    });

    test('nests the three cached permission booleans', () {
      final permissions =
          ServerUserRow.of(row())['permissions'] as Map<String, dynamic>;
      expect(permissions['is_server_admin'], isTrue);
      expect(permissions['is_channel_manager'], isFalse);
      expect(permissions['can_create_tokens'], isTrue);
    });

    test('drops what the client has no use for', () {
      // The shape is a contract, not a passthrough — a row that grew a column
      // should not quietly grow the model.
      expect(ServerUserRow.of(row()).containsKey('created_at'), isFalse);
    });

    test('a missing column comes through as null rather than throwing', () {
      // Selects differ between call sites, and a member list that threw on one
      // absent column would take the whole roster with it.
      final out = ServerUserRow.of({'id': 'u1'});
      expect(out['id'], 'u1');
      expect(out['username'], isNull);
      expect(out['is_bot'], isNull);
    });
  });

  group('folding in permission bits', () {
    test('keeps the booleans alongside the bits', () {
      // Both arrive as one answer on purpose: a client reconciling two would
      // have to decide which wins, and there is no right answer to that.
      final out = ServerUserRow.withPermissionBits(ServerUserRow.of(row()), 5);
      final permissions = out['permissions'] as Map<String, dynamic>;
      expect(permissions['permission_bits'], 5);
      expect(permissions['is_server_admin'], isTrue);
    });

    test('leaves the rest of the row alone', () {
      final out = ServerUserRow.withPermissionBits(ServerUserRow.of(row()), 5);
      expect(out['username'], 'sam');
    });
  });

  group('reading the subject out of a token', () {
    String token(Map<String, dynamic> payload) {
      String seg(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      return '${seg({'alg': 'HS256'})}.${seg(payload)}.sig';
    }

    test('finds the sub claim', () {
      expect(ServerUserRow.uidOf(token({'sub': 'u1'})), 'u1');
    });

    test('answers null for anything it cannot read', () {
      // Never throws: this is the client reading its own token to know which
      // row is "mine", and the server re-checks anyway. A malformed token is a
      // question with no answer, not a crash.
      expect(ServerUserRow.uidOf(null), isNull);
      expect(ServerUserRow.uidOf('not a jwt'), isNull);
      expect(ServerUserRow.uidOf('a.b.c'), isNull);
      expect(ServerUserRow.uidOf(token({'no': 'sub'})), isNull);
    });
  });
}
