import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/services/server_import_merge.dart';

/// Reconciling the server list against a restored vault backup.
///
/// The bug this exists to stop: the match was on `supabaseUrl` alone, and one
/// Supabase project hosts as many servers as its operator wants. A device
/// that knew three servers on one host, restoring a backup holding those same
/// three, came out with three copies of one of them and the other two gone.
/// It is invisible from inside the function — every entry found *a* match.
void main() {
  const host = 'http://192.168.1.6:18000';
  const other = 'http://localhost:8000';

  Server server(String id, String name, {String url = host}) => Server(
    id: id,
    name: name,
    supabaseUrl: url,
    token: 'live-token',
    tokenIssuedAt: DateTime(2026, 9, 20),
  );

  Map<String, dynamic> entry(String? id, String name, {String url = host}) => {
    'id': ?id,
    'name': name,
    'supabaseUrl': url,
    'keyVersion': 'v1',
  };

  group('a backup holding several servers on one project', () {
    test('keeps each of them, rather than copies of one', () {
      final restored = ServerImportMerge.apply(
        existing: [
          server('a', 'Rotation Test'),
          server('b', 'Mobile Test'),
          server('c', 'Proxy Test'),
        ],
        imported: [
          entry('a', 'Rotation Test'),
          entry('b', 'Mobile Test'),
          entry('c', 'Proxy Test'),
        ],
      );
      expect(restored.map((s) => s.id), ['a', 'b', 'c']);
      expect(restored.map((s) => s.name), [
        'Rotation Test',
        'Mobile Test',
        'Proxy Test',
      ]);
    });

    test('and never lists one twice', () {
      final restored = ServerImportMerge.apply(
        existing: [server('a', 'Rotation Test')],
        imported: [entry('a', 'Rotation Test'), entry('a', 'Rotation Test')],
      );
      expect(restored.length, 1);
    });
  });

  test('a server the device does not know is rebuilt from the backup', () {
    final restored = ServerImportMerge.apply(
      existing: const [],
      imported: [entry('a', 'Proxy Test')],
    );
    expect(restored.single.name, 'Proxy Test');
    // Empty, not carried: there is no session for an identity this device has
    // only just restored.
    expect(restored.single.token, isEmpty);
    expect(restored.single.tokenIssuedAt, ServerImportMerge.stale);
  });

  test('a known server keeps what it knows but loses its session', () {
    final restored = ServerImportMerge.apply(
      existing: [server('a', 'Proxy Test')],
      imported: [entry('a', 'Proxy Test')],
    );
    expect(restored.single.token, 'live-token');
    expect(restored.single.tokenIssuedAt, ServerImportMerge.stale);
  });

  test('a server the backup does not mention is dropped', () {
    final restored = ServerImportMerge.apply(
      existing: [server('a', 'Kept'), server('b', 'Left behind')],
      imported: [entry('a', 'Kept')],
    );
    expect(restored.map((s) => s.id), ['a']);
  });

  test('two projects are not confused by a shared server id', () {
    // Ids are minted per server database, so nothing stops the same UUID
    // existing on two hosts. Matching on the pair is what keeps them apart.
    final restored = ServerImportMerge.apply(
      existing: [
        server('a', 'Here'),
        server('a', 'There', url: other),
      ],
      imported: [
        entry('a', 'Here'),
        entry('a', 'There', url: other),
      ],
    );
    expect(restored.map((s) => s.supabaseUrl), [host, other]);
    expect(restored.map((s) => s.name), ['Here', 'There']);
  });

  group('a legacy v1 backup, which recorded hosts and not servers', () {
    test('keeps every server the device knows on that host', () {
      // One entry, no id — the only honest reading is "this identity has
      // joined this project", which says nothing about which servers on it.
      final restored = ServerImportMerge.apply(
        existing: [
          server('a', 'One'),
          server('b', 'Two'),
          server('c', 'Three'),
        ],
        imported: [
          {'supabaseUrl': host, 'keyVersion': 'v1'},
        ],
      );
      expect(restored.map((s) => s.id), ['a', 'b', 'c']);
      expect(
        restored.every((s) => s.tokenIssuedAt == ServerImportMerge.stale),
        isTrue,
      );
    });

    test('and cannot invent one the device has never seen', () {
      final restored = ServerImportMerge.apply(
        existing: const [],
        imported: [
          {'supabaseUrl': host, 'keyVersion': 'v1'},
        ],
      );
      expect(restored, isEmpty);
    });
  });

  group('deduplicate', () {
    test('heals a list already holding the same server several times', () {
      final duplicated = [
        server('a', 'Rift'),
        server('a', 'Rift'),
        server('a', 'Rift'),
        server('b', 'S3', url: other),
      ];
      final healed = ServerImportMerge.deduplicate(duplicated);
      expect(healed.map((s) => s.id), ['a', 'b']);
    });

    test('leaves a clean list exactly as it is', () {
      final clean = [server('a', 'One'), server('b', 'Two', url: other)];
      expect(ServerImportMerge.deduplicate(clean), clean);
    });
  });
}
