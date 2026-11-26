import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/services/server_realtime.dart';
import 'package:rift/logic/services/voice_broadcast.dart';
import 'package:rift/logic/services/voice_locations.dart';
import 'package:supabase/supabase.dart' show RealtimeSubscribeStatus;

// A port nothing listens on, so no socket is ever really open.
final _server = Server.fromJoin('http://127.0.0.1:9/a', 'jwt', {
  'server_id': 'a',
  'name': 'a',
  'supabase_key': 'anon',
});

/// Each roster read is `voice_roster`, an edge function. A join right after
/// the read made at construction counts on that read; a later one, or the
/// topic opening again, reads.
void main() {
  late StreamController<List<Server>> servers;
  late ServerRealtime realtime;
  late int reads;
  late VoiceBroadcast voice;

  setUp(() {
    servers = StreamController<List<Server>>.broadcast();
    realtime = ServerRealtime(
      servers: servers.stream,
      current: () => [_server],
      post: (url, {headers, body}) async => http.Response('', 202),
    );
    reads = 0;
    voice = VoiceBroadcast(
      realtime: realtime,
      server: _server,
      userId: 'me',
      fetchRoster: () async {
        reads++;
        return (locations: <String, String>{}, sharing: <String>{});
      },
      onChanged: () {},
    );
  });

  tearDown(() async {
    await voice.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await realtime.dispose();
    await servers.close();
  });

  void joined() => realtime.debugReportStatus(
    'a',
    VoiceLocations.topic('a'),
    RealtimeSubscribeStatus.subscribed,
  );

  test('a join just after the first read asks nothing more', () async {
    expect(reads, 1);
    joined();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);

    // The topic opening again is a new start: whatever moved meanwhile.
    joined();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);
  });

  test('a join that comes later reads again', () async {
    await Future<void>.delayed(
      VoiceBroadcast.firstReadServesJoinWithin +
          const Duration(milliseconds: 100),
    );
    joined();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);
  });
}
