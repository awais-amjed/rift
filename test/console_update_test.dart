import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/console_update.dart';
import 'package:rift/data/classes/server_details.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';

import 'support/memory_storage.dart';

const _me = {'id': 'u1', 'username': 'ada', 'display_name': 'Ada'};
const _update = {
  'version': '1.7.0',
  'url': 'https://example.test/1.7.0',
  'notes': 'new things',
};

/// A server tells its admins when its console has a newer release
/// (`console_update`, rift-self-host 029). An older server says nothing,
/// which must not take away what a newer reply said; a reply that says null
/// has nothing to tell, and must.
void main() {
  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the reply carries the release', () {
    final details = ServerDetails.fromJson({'console_update': _update});
    expect(details.consoleUpdateStated, isTrue);
    expect(
      details.consoleUpdate,
      const ConsoleUpdate(
        version: '1.7.0',
        url: 'https://example.test/1.7.0',
        notes: 'new things',
      ),
    );
  });

  test('null is an answer, silence is not', () {
    final none = ServerDetails.fromJson({'console_update': null});
    expect(none.consoleUpdateStated, isTrue);
    expect(none.consoleUpdate, isNull);
    final old = ServerDetails.fromJson({'name': 'x'});
    expect(old.consoleUpdateStated, isFalse);
  });

  test('a shape the app does not know reads as nothing to tell', () {
    final odd = ServerDetails.fromJson({
      'console_update': {'version': 3},
    });
    expect(odd.consoleUpdate, isNull);
  });

  test('a server lands it, keeps it through silence, drops it on null', () {
    final cubit = ServerCubit(session: SessionRepository());
    cubit.addServer('https://server.invalid', 'jwt', {
      'server_id': 'srv-1',
      'name': 'Rift HQ',
      'supabase_key': 'anon-key',
      'user': _me,
      'channels': <Map<String, dynamic>>[],
    });
    ConsoleUpdate? held() => cubit.state.servers.single.consoleUpdate;

    cubit.applyServerDetails(
      'srv-1',
      ServerDetails.fromJson({'console_update': _update}),
    );
    expect(held()?.version, '1.7.0');

    cubit.applyServerDetails('srv-1', ServerDetails.fromJson({'name': 'x'}));
    expect(held()?.version, '1.7.0');

    cubit.applyServerDetails(
      'srv-1',
      ServerDetails.fromJson({'console_update': null}),
    );
    expect(held(), isNull);
  });

  test('it is not saved with the server', () {
    final cubit = ServerCubit(session: SessionRepository());
    cubit.addServer('https://server.invalid', 'jwt', {
      'server_id': 'srv-1',
      'name': 'Rift HQ',
      'user': _me,
    });
    cubit.applyServerDetails(
      'srv-1',
      ServerDetails.fromJson({'console_update': _update}),
    );
    final json = cubit.state.servers.single.toJson();
    expect(
      json.keys.where((k) => k.toLowerCase().contains('console')),
      isEmpty,
    );
  });
}
