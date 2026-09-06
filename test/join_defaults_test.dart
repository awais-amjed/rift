import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/join_defaults.dart';

void main() {
  Server server(String username, String displayName) => Server(
    id: username,
    name: 'S',
    supabaseUrl: 'https://$username.example',
    token: 't',
    user: ServerUser(
      id: 'u',
      username: username,
      displayName: displayName,
      permissions: const UserPermissions(),
    ),
  );

  group('join defaults', () {
    test('the central handle is the username, and nothing else is', () {
      final d = JoinDefaults.of(centralHandle: 'noor', servers: const []);
      expect(d.username, 'noor');
      expect(d.displayName, '');
    });

    test('without a central account the username is left to be typed', () {
      final d = JoinDefaults.of(
        centralHandle: null,
        servers: [server('noor_on_a', 'Noor')],
      );
      expect(d.username, '');
      expect(d.displayName, 'Noor');
    });

    test('the display name follows the most recent server', () {
      final d = JoinDefaults.of(
        centralHandle: 'noor',
        servers: [server('a', 'Old Name'), server('b', 'Noor A.')],
      );
      expect(d.displayName, 'Noor A.');
    });
  });
}
