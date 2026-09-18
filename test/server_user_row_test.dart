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
}
