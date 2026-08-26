import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/push_wake/wake_index.dart';

/// The snapshot the app leaves for the push background isolate.
///
/// The isolate cannot ask the app anything, so a field missing or misread here
/// is a server it silently cannot open. Round-tripping and rejecting malformed
/// rows is the whole contract.
WakeServer server({
  String id = 's1',
  String name = 'Rift HQ',
  String url = 'https://example.supabase.co',
  String user = 'u1',
  String username = 'noor',
  String keyVersion = 'v1',
  Map<String, String> channels = const {'c1': 'general'},
}) => WakeServer(
  id: id,
  name: name,
  supabaseUrl: url,
  anonKey: 'anon',
  userId: user,
  username: username,
  keyVersion: keyVersion,
  channels: channels,
);

void main() {
  test('a server round-trips through json', () {
    final restored = WakeServer.fromJson(server().toJson())!;
    expect(restored.id, 's1');
    expect(restored.name, 'Rift HQ');
    expect(restored.supabaseUrl, 'https://example.supabase.co');
    expect(restored.anonKey, 'anon');
    expect(restored.userId, 'u1');
    expect(restored.username, 'noor');
    expect(restored.keyVersion, 'v1');
    expect(restored.channels, {'c1': 'general'});
  });

  test('a row without the fields a wake needs is dropped, not guessed', () {
    expect(WakeServer.fromJson({'name': 'Rift HQ'}), isNull);
    expect(WakeServer.fromJson({'id': 's1', 'url': 'x'}), isNull);
  });

  test('missing optional fields fall back rather than throwing', () {
    final restored = WakeServer.fromJson({
      'id': 's1',
      'url': 'https://example.supabase.co',
      'user': 'u1',
    })!;
    expect(restored.name, 'Rift');
    expect(restored.username, '');
    expect(restored.keyVersion, 'v1');
    expect(restored.channels, isEmpty);
  });

  test('identical snapshots compare equal, so nothing is rewritten', () {
    expect(server().sameAs(server()), isTrue);
    expect(
      WakeIndex(servers: [server()]).sameAs(WakeIndex(servers: [server()])),
      isTrue,
    );
  });

  test('a renamed channel is a change the isolate would notice', () {
    expect(server().sameAs(server(channels: const {'c1': 'lounge'})), isFalse);
    expect(server().sameAs(server(keyVersion: 'v2')), isFalse);
    expect(server().sameAs(server(username: 'sam')), isFalse);
  });

  test('a different number of servers is a change', () {
    expect(WakeIndex(servers: [server()]).sameAs(const WakeIndex()), isFalse);
  });
}
