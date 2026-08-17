import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';

/// [ServerState.serverById] is what every per-server API call resolves through,
/// so the thing worth pinning is where it *differs* from [ServerState
/// .selectedServer]: it never substitutes another server. A dialog opened for
/// one server silently writing to another is the bug it exists to prevent.
void main() {
  Server server(String id) => Server(
    id: id,
    name: 'Server $id',
    supabaseUrl: 'http://localhost:8000',
    token: 'tok-$id',
    tokenIssuedAt: DateTime.now(),
  );

  ServerState state({String? selected}) => ServerState(
    servers: [server('a'), server('b')],
    selectedServerId: selected,
  );

  group('serverById', () {
    test('finds a joined server whether or not it is selected', () {
      final s = state(selected: 'a');
      expect(s.serverById('a')?.id, 'a');
      expect(s.serverById('b')?.id, 'b');
    });

    test('is null for an id this device does not have', () {
      expect(state(selected: 'a').serverById('gone'), isNull);
    });

    test('does not fall back to another server, where selectedServer does', () {
      // A selection pointing at a server that has been left resolves to
      // whatever is first — fine for "show me something", wrong for a write.
      final stale = ServerState(
        servers: [server('a'), server('b')],
        selectedServerId: 'gone',
      );
      expect(stale.selectedServer?.id, 'a');
      expect(stale.serverById('gone'), isNull);
    });

    test('is null when there are no servers at all', () {
      expect(const ServerState().serverById('a'), isNull);
    });
  });
}
