import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/message_cache_slot.dart';
import 'package:rift/logic/services/message_cache.dart';
import 'package:rift/logic/services/saved_conversation.dart';
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

void main() {
  late Directory root;
  late MessageCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rift_saved_conv_test');
    cache = MessageCache(root: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test(
    'writes the fetched page, with what the surface keeps beside it',
    () async {
      final saved = SavedConversation(
        cache: cache,
        extras: () => {
          'keys': {'1': 'k'},
        },
      );
      await saved.open(seed, channel('a'));
      saved.replace([row(2), row(1)]);
      await saved.flush();

      final copy = await cache.read(seed, channel('a'));
      expect(idsIn(copy), [2, 1]);
      expect(copy!['keys'], {'1': 'k'});
      saved.dispose();
    },
  );

  test('own sends are fetched once, from the first of them', () async {
    final asked = <int>[];
    final saved = SavedConversation(cache: cache);
    await saved.open(
      seed,
      channel('a'),
      rowsAfter: (afterId) async {
        asked.add(afterId);
        return [row(11), row(12)];
      },
    );
    saved.replace([row(10)]);
    saved
      ..noteSent('12')
      ..noteSent('11');
    await saved.flush();

    expect(asked, [10]);
    expect(idsIn(await cache.read(seed, channel('a'))), [12, 11, 10]);

    // Nothing new sent: the next write does not ask again.
    saved.merge([row(13)]);
    await saved.flush();
    expect(asked, [10]);
    saved.dispose();
  });

  test(
    'a flush started as another conversation opens saves the one left',
    () async {
      final saved = SavedConversation(cache: cache);
      await saved.open(seed, channel('a'));
      saved.replace([row(1)]);

      final leaving = saved.flush();
      await saved.open(seed, channel('b'));
      await leaving;

      expect(idsIn(await cache.read(seed, channel('a'))), [1]);
      expect(await cache.read(seed, channel('b')), isNull);
      saved.dispose();
    },
  );

  test(
    'nothing is written when the surface says it could not be opened',
    () async {
      final saved = SavedConversation(cache: cache, canSave: () => false);
      await saved.open(seed, channel('a'));
      saved.replace([row(1)]);
      await saved.flush();
      expect(await cache.read(seed, channel('a')), isNull);
      saved.dispose();
    },
  );

  test('an emptied conversation loses its copy', () async {
    final saved = SavedConversation(cache: cache);
    await saved.open(seed, channel('a'));
    saved.replace([row(1)]);
    await saved.flush();
    saved.remove('1');
    await saved.flush();
    expect(await cache.read(seed, channel('a')), isNull);
    saved.dispose();
  });

  test('discard writes nothing of what was pending', () async {
    final saved = SavedConversation(cache: cache);
    await saved.open(seed, channel('a'));
    saved
      ..replace([row(1)])
      ..discard();
    await saved.flush();
    expect(await cache.read(seed, channel('a')), isNull);
  });
}
