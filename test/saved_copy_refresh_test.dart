import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/message_cache_slot.dart';
import 'package:rift/logic/services/message_cache.dart';
import 'package:rift/logic/services/saved_conversation.dart';
import 'package:rift/logic/services/saved_copy_refresh.dart';
import 'package:rift/logic/services/saved_tail.dart';
import 'package:rift_crypto/rift_crypto.dart';

final seed = CryptoRepository.toBase64(Uint8List.fromList(List.filled(32, 3)));

MessageCacheSlot channel(String id) => MessageCacheSlot.channel(
  supabaseUrl: 'https://chat.example.org',
  serverId: 's1',
  channelId: id,
);

Map<String, dynamic> row(int id) => {'id': id};

List<int> idsIn(Map<String, dynamic>? saved) => [
  for (final r in SavedConversation.rowsOf(saved!)) r['id'] as int,
];

/// Lets every queued read and write of the cache finish.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory root;
  late MessageCache cache;
  late SavedCopyRefresh refresh;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rift_saved_refresh_test');
    cache = MessageCache(root: () async => root);
    refresh = SavedCopyRefresh(cache: cache);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('asks only for what is newer, adds it, and keeps the keys', () async {
    await cache.write(seed, channel('a'), {
      'keys': {'1': 'k'},
      'rows': [row(2), row(1)],
    });
    final asked = <int?>[];

    refresh.refresh(seed, channel('a'), (afterId) async {
      asked.add(afterId);
      return [row(3)];
    });
    await settle();

    final copy = await cache.read(seed, channel('a'));
    expect(asked, [2]);
    expect(idsIn(copy), [3, 2, 1]);
    expect(copy!['keys'], {'1': 'k'});
  });

  test('more than a page newer replaces the copy, leaving no gap', () async {
    await cache.write(seed, channel('a'), {
      'rows': [row(1)],
    });
    final asked = <int?>[];
    final page = [for (var id = 200; id > 200 - SavedTail.size; id--) row(id)];

    refresh.refresh(seed, channel('a'), (afterId) async {
      asked.add(afterId);
      return afterId == null
          ? page
          : [for (var id = 2; id < 2 + SavedTail.size; id++) row(id)];
    });
    await settle();

    expect(asked, [1, null]);
    expect(idsIn(await cache.read(seed, channel('a'))), [
      for (final r in page) r['id'],
    ]);
  });

  test('asks nothing for a conversation with no copy', () async {
    var asked = 0;
    refresh.refresh(seed, channel('a'), (_) async {
      asked++;
      return [row(1)];
    });
    await settle();

    expect(asked, 0);
    expect(await cache.read(seed, channel('a')), isNull);
  });

  test('a burst while a read is out is one more read, not one each', () async {
    await cache.write(seed, channel('a'), {
      'rows': [row(1)],
    });
    var asked = 0;
    final first = Completer<List<Map<String, dynamic>>?>();
    Future<List<Map<String, dynamic>>?> page(int? afterId) {
      asked++;
      return asked == 1 ? first.future : Future.value([row(4), row(3)]);
    }

    refresh.refresh(seed, channel('a'), page);
    await settle();
    for (var i = 0; i < 3; i++) {
      refresh.refresh(seed, channel('a'), page);
    }
    first.complete([row(2), row(1)]);
    await settle();

    expect(asked, 2);
    expect(idsIn(await cache.read(seed, channel('a'))), [4, 3, 2, 1]);
  });

  test('a failed read leaves the copy as it was', () async {
    await cache.write(seed, channel('a'), {
      'rows': [row(1)],
    });

    refresh.refresh(seed, channel('a'), (_) async => null);
    await settle();
    refresh.refresh(seed, channel('a'), (_) async => throw StateError('down'));
    await settle();

    expect(idsIn(await cache.read(seed, channel('a'))), [1]);
  });
}
