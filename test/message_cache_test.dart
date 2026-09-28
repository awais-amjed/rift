import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/message_cache_slot.dart';
import 'package:rift/logic/services/message_cache.dart';
import 'package:rift_crypto/rift_crypto.dart';

String seedOf(int fill) =>
    CryptoRepository.toBase64(Uint8List.fromList(List.filled(32, fill)));

void main() {
  final seed = seedOf(1);
  final channel = MessageCacheSlot.channel(
    supabaseUrl: 'https://chat.example.org',
    serverId: 's1',
    channelId: 'c1',
  );
  final data = {
    'rows': [
      {'id': 1, 'sender_name': 'Emma', 'ciphertext': 'a webhook said this'},
    ],
  };

  late Directory root;
  late MessageCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rift_message_cache_test');
    cache = MessageCache(root: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  List<File> files() =>
      root.listSync(recursive: true).whereType<File>().toList();

  group('MessageCache', () {
    test('reads back what it saved', () async {
      await cache.write(seed, channel, data);
      expect(await cache.read(seed, channel), data);
    });

    test('nothing saved reads as null', () async {
      expect(await cache.read(seed, channel), isNull);
    });

    test('is sealed: no name, text or address appears on the disk', () async {
      await cache.write(seed, channel, data);
      for (final file in files()) {
        final text = String.fromCharCodes(file.readAsBytesSync());
        expect(text, isNot(contains('Emma')));
        expect(text, isNot(contains('webhook')));
        expect(file.path, isNot(contains('example')));
        expect(file.path, isNot(contains('c1')));
      }
    });

    test('another seed cannot open it', () async {
      await cache.write(seed, channel, data);
      expect(await cache.read(seedOf(2), channel), isNull);
    });

    test('a copy moved onto another conversation is refused', () async {
      final other = MessageCacheSlot.channel(
        supabaseUrl: 'https://chat.example.org',
        serverId: 's1',
        channelId: 'c2',
      );
      await cache.write(seed, channel, data);
      await cache.write(seed, other, {'rows': []});

      final byName = {for (final f in files()) f.path: f.readAsBytesSync()};
      final paths = byName.keys.toList();
      // Swap the two files' contents.
      File(paths[0]).writeAsBytesSync(byName[paths[1]]!);
      File(paths[1]).writeAsBytesSync(byName[paths[0]]!);

      expect(await cache.read(seed, channel), isNull);
      expect(await cache.read(seed, other), isNull);
    });

    test('a tampered file reads as null rather than throwing', () async {
      await cache.write(seed, channel, data);
      final file = files().single;
      final bytes = file.readAsBytesSync();
      bytes[bytes.length - 1] ^= 1;
      file.writeAsBytesSync(bytes);
      expect(await cache.read(seed, channel), isNull);
    });

    test('forget removes one conversation and leaves the rest', () async {
      final dm = MessageCacheSlot.serverDm(
        supabaseUrl: 'https://chat.example.org',
        serverId: 's1',
        peerId: 'p1',
      );
      await cache.write(seed, channel, data);
      await cache.write(seed, dm, data);
      await cache.forget(seed, channel);
      expect(await cache.read(seed, channel), isNull);
      expect(await cache.read(seed, dm), data);
    });

    test('forgetting a server leaves the others and central', () async {
      final otherServer = MessageCacheSlot.channel(
        supabaseUrl: 'https://chat.example.org',
        serverId: 's2',
        channelId: 'c1',
      );
      final central = MessageCacheSlot.centralDm(peerId: 'p1');
      await cache.write(seed, channel, data);
      await cache.write(seed, otherServer, data);
      await cache.write(seed, central, data);

      for (final scope in MessageCacheSlot.scopesOfServer(
        'https://chat.example.org',
        's1',
      )) {
        await cache.forgetScope(seed, scope);
      }

      expect(await cache.read(seed, channel), isNull);
      expect(await cache.read(seed, otherServer), data);
      expect(await cache.read(seed, central), data);
    });

    test('forgetting a server takes its DMs too', () async {
      final dm = MessageCacheSlot.serverDm(
        supabaseUrl: 'https://chat.example.org',
        serverId: 's1',
        peerId: 'p1',
      );
      await cache.write(seed, dm, data);
      for (final scope in MessageCacheSlot.scopesOfServer(
        'https://chat.example.org',
        's1',
      )) {
        await cache.forgetScope(seed, scope);
      }
      expect(await cache.read(seed, dm), isNull);
    });

    test(
      'keepOnly prunes channels the server no longer lists, not DMs',
      () async {
        MessageCacheSlot channelSlot(String id) => MessageCacheSlot.channel(
          supabaseUrl: 'https://chat.example.org',
          serverId: 's1',
          channelId: id,
        );
        final dm = MessageCacheSlot.serverDm(
          supabaseUrl: 'https://chat.example.org',
          serverId: 's1',
          peerId: 'p1',
        );
        await cache.write(seed, channelSlot('kept'), data);
        await cache.write(seed, channelSlot('gone'), data);
        await cache.write(seed, dm, data);

        await cache.keepOnly(
          seed,
          MessageCacheSlot.serverScope('https://chat.example.org', 's1'),
          [channelSlot('kept')],
        );

        expect(await cache.read(seed, channelSlot('kept')), data);
        expect(await cache.read(seed, channelSlot('gone')), isNull);
        expect(await cache.read(seed, dm), data);
      },
    );

    test('a save asked for after a server is left writes nothing', () async {
      await cache.write(seed, channel, data);
      final scopes = MessageCacheSlot.scopesOfServer(
        'https://chat.example.org',
        's1',
      );
      // Not awaited: the cubits' flushes are asked for right behind the
      // wipe, and must still lose to it.
      for (final scope in scopes) {
        unawaited(cache.forgetScope(seed, scope));
      }
      await cache.write(seed, channel, data);
      expect(await cache.read(seed, channel), isNull);

      // Joined again: saving works again.
      scopes.forEach(cache.reopenScope);
      await cache.write(seed, channel, data);
      expect(await cache.read(seed, channel), data);
    });

    test('nothing is saved under a seed after its vault is reset', () async {
      await cache.write(seed, channel, data);
      unawaited(cache.clear());
      await cache.write(seed, channel, data);
      expect(root.existsSync(), isFalse);

      // A new identity saves as normal.
      await cache.write(seedOf(9), channel, data);
      expect(await cache.read(seedOf(9), channel), data);
    });

    test('clear removes everything', () async {
      await cache.write(seed, channel, data);
      await cache.write(seed, MessageCacheSlot.centralDm(peerId: 'p1'), data);
      await cache.clear();
      expect(root.existsSync(), isFalse);
      expect(await cache.read(seed, channel), isNull);
    });
  });

  group('MessageCacheSlot', () {
    test('the same channel on two servers in one project is two slots', () {
      final a = MessageCacheSlot.channel(
        supabaseUrl: 'https://p.example.org',
        serverId: 's1',
        channelId: 'c',
      );
      final b = MessageCacheSlot.channel(
        supabaseUrl: 'https://p.example.org',
        serverId: 's2',
        channelId: 'c',
      );
      expect(a, isNot(b));
      expect(a.label, isNot(b.label));
    });

    test('a channel and a DM with the same id are two slots', () {
      final channel = MessageCacheSlot.channel(
        supabaseUrl: 'u',
        serverId: 's',
        channelId: 'x',
      );
      final dm = MessageCacheSlot.serverDm(
        supabaseUrl: 'u',
        serverId: 's',
        peerId: 'x',
      );
      expect(channel.label, isNot(dm.label));
    });
  });

  test('the cache key is its own rung of the ladder', () async {
    final crypto = CryptoRepository();
    final bytes = CryptoRepository.fromBase64(seed);
    final cacheKey = await crypto.deriveMessageCacheKey(bytes);
    expect(cacheKey, hasLength(32));
    expect(cacheKey, isNot(await crypto.deriveLocalVaultKey(bytes)));
    expect(cacheKey, await crypto.deriveMessageCacheKey(bytes));
    expect(
      cacheKey,
      isNot(
        await crypto.deriveMessageCacheKey(
          CryptoRepository.fromBase64(seedOf(2)),
        ),
      ),
    );
  });
}
