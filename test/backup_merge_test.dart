import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/backup_merge.dart';

void main() {
  Map<String, dynamic> server(
    String id, {
    String url = 'https://one.example',
    String? name,
    String? iconUrl,
  }) => {
    'id': id,
    'name': name ?? id,
    'iconUrl': iconUrl,
    'supabaseUrl': url,
    'supabaseKey': 'key',
    'livekitUrl': 'wss://lk.example',
    'keyVersion': 'v1',
  };

  List<String> idsOf(ServerManifest m) =>
      m.servers.map((e) => e['id'] as String).toList();

  group('what a backup carries', () {
    test('a v1 bare array still reads, with no opinion about order', () {
      final manifest = ServerManifest.decode([server('a'), server('b')]);
      expect(idsOf(manifest), ['a', 'b']);
      expect(manifest.orderClock, 0);
    });

    test('and the v2 object round-trips', () {
      const original = ServerManifest(servers: [], orderClock: 7);
      final back = ServerManifest.decode(original.encode());
      expect(back.orderClock, 7);
    });

    test('anything else is an empty list, not a crash', () {
      // A truncated or foreign blob must not take the rail down with it.
      expect(ServerManifest.decode(null).servers, isEmpty);
      expect(ServerManifest.decode('nonsense').servers, isEmpty);
      expect(ServerManifest.decode({'servers': 'nonsense'}).servers, isEmpty);
    });
  });

  group('merging for upload', () {
    test('a server only the other device knows is kept', () {
      // The case that makes this exist: join on the phone, then the laptop's
      // auto-backup lands. A blind upsert loses the phone's server.
      final merged = BackupMerge.union(
        mine: ServerManifest(servers: [server('a')]),
        theirs: ServerManifest(servers: [server('a'), server('b')]),
      );
      expect(idsOf(merged), containsAll(['a', 'b']));
    });

    test('and a server only this device knows is kept too', () {
      final merged = BackupMerge.union(
        mine: ServerManifest(servers: [server('a'), server('b')]),
        theirs: ServerManifest(servers: [server('a')]),
      );
      expect(idsOf(merged), containsAll(['a', 'b']));
    });

    test('two servers on one host stay two servers', () {
      // The collapse `ServerImportMerge` was written for, in the other
      // direction: keyed on the URL alone these would be one entry.
      final merged = BackupMerge.union(
        mine: ServerManifest(servers: [server('a'), server('b')]),
        theirs: ServerManifest(servers: [server('a'), server('b')]),
      );
      expect(idsOf(merged), ['a', 'b']);
    });

    test('the newer order wins, whichever side holds it', () {
      final mine = ServerManifest(
        servers: [server('a'), server('b')],
        orderClock: 1,
      );
      final theirs = ServerManifest(
        servers: [server('b'), server('a')],
        orderClock: 2,
      );
      expect(idsOf(BackupMerge.union(mine: mine, theirs: theirs)), ['b', 'a']);
      expect(idsOf(BackupMerge.union(mine: theirs, theirs: mine)), ['b', 'a']);
    });

    test('a tie goes to the device doing the writing', () {
      final mine = ServerManifest(
        servers: [server('a'), server('b')],
        orderClock: 3,
      );
      final theirs = ServerManifest(
        servers: [server('b'), server('a')],
        orderClock: 3,
      );
      expect(idsOf(BackupMerge.union(mine: mine, theirs: theirs)), ['a', 'b']);
    });

    test('the clock only ever goes up', () {
      final merged = BackupMerge.union(
        mine: const ServerManifest(servers: [], orderClock: 2),
        theirs: const ServerManifest(servers: [], orderClock: 9),
      );
      expect(merged.orderClock, 9);
      expect(BackupMerge.nextClock(mine: 2, theirs: 9), 10);
      expect(BackupMerge.nextClock(mine: 9, theirs: 2), 10);
    });

    test('a server the loser holds lands after the winner\'s order', () {
      // The order is an opinion about the servers the chooser could see. One
      // it had never heard of cannot have a place in it, so it goes last
      // rather than somewhere invented.
      final merged = BackupMerge.union(
        mine: ServerManifest(servers: [server('c')], orderClock: 1),
        theirs: ServerManifest(
          servers: [server('b'), server('a')],
          orderClock: 5,
        ),
      );
      expect(idsOf(merged), ['b', 'a', 'c']);
    });

    test('a stub does not blank what the cloud still remembers', () {
      // A freshly restored device holds id/name/url and nulls; uploading
      // those as-is would push the gaps out to every other device.
      final merged = BackupMerge.union(
        mine: ServerManifest(
          servers: [
            {'id': 'a', 'name': 'a', 'supabaseUrl': 'https://one.example'},
          ],
        ),
        theirs: ServerManifest(
          servers: [server('a', iconUrl: 'https://cdn/icon.png')],
        ),
      );
      expect(merged.servers.single['iconUrl'], 'https://cdn/icon.png');
      expect(merged.servers.single['livekitUrl'], 'wss://lk.example');
    });

    test('but a field this device has changed does win', () {
      final merged = BackupMerge.union(
        mine: ServerManifest(servers: [server('a', name: 'Renamed')]),
        theirs: ServerManifest(servers: [server('a', name: 'Old')]),
      );
      expect(merged.servers.single['name'], 'Renamed');
    });

    test('an entry with no url is dropped rather than merged', () {
      final merged = BackupMerge.union(
        mine: ServerManifest(
          servers: [
            server('a'),
            {'id': 'ghost', 'name': 'ghost'},
          ],
        ),
        theirs: ServerManifest.empty,
      );
      expect(idsOf(merged), ['a']);
    });

    test('a v1 host record gives way to the real servers on that host', () {
      // v1 recorded projects, not servers. Beside a real server on the same
      // host it would restore as a nameless stub belonging to nobody.
      final merged = BackupMerge.union(
        mine: ServerManifest(servers: [server('a')]),
        theirs: const ServerManifest(
          servers: [
            {'supabaseUrl': 'https://one.example', 'keyVersion': 'v1'},
          ],
        ),
      );
      expect(merged.servers.length, 1);
      expect(merged.servers.single['id'], 'a');
    });

    test('and survives on its own when nothing else covers that host', () {
      final merged = BackupMerge.union(
        mine: ServerManifest(servers: [server('a')]),
        theirs: const ServerManifest(
          servers: [
            {'supabaseUrl': 'https://two.example', 'keyVersion': 'v1'},
          ],
        ),
      );
      expect(merged.servers.length, 2);
    });

    test('merging with an empty cloud copy changes nothing', () {
      final mine = ServerManifest(
        servers: [server('a'), server('b')],
        orderClock: 4,
      );
      final merged = BackupMerge.union(
        mine: mine,
        theirs: ServerManifest.empty,
      );
      expect(idsOf(merged), ['a', 'b']);
      expect(merged.orderClock, 4);
    });
  });
}
