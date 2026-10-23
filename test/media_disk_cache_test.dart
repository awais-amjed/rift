import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/media_entry.dart';
import 'package:rift/logic/services/media_disk_cache.dart';
import 'package:rift/logic/services/media_store.dart';

/// Avatars and icons kept on disk between runs, so a restart draws them
/// without downloading each one again.
void main() {
  const host = 'https://chat.example.org';
  const path = 'b1946ac9-0000-4000-8000-000000000001/0a1b2c3d4e5f.img';
  final pic = Uint8List.fromList([1, 2, 3, 4]);

  late Directory root;
  MediaDiskCache cacheOf({int maxBytes = 1 << 20}) =>
      MediaDiskCache(root: () async => root, maxBytes: maxBytes);

  setUp(() => root = Directory.systemTemp.createTempSync('rift_pictures_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  List<File> files() =>
      root.existsSync() ? root.listSync().whereType<File>().toList() : const [];

  group('MediaDiskCache', () {
    test('reads back what it saved, and nothing saved reads as null', () async {
      final cache = cacheOf();
      expect(await cache.read(host, path), isNull);
      await cache.write(host, path, pic);
      expect(await cache.read(host, path), pic);
    });

    test('the same path from another host is not the same picture', () async {
      // A server repeating another's path must not leave its bytes for it.
      final cache = cacheOf();
      await cache.write('https://other.example', path, pic);
      expect(await cache.read(host, path), isNull);
    });

    test('a file name says neither the host nor the path', () async {
      await cacheOf().write(host, path, pic);
      for (final file in files()) {
        final name = file.uri.pathSegments.last;
        expect(name, isNot(contains('example')));
        expect(name, isNot(contains('b1946ac9')));
      }
    });

    test('clear leaves nothing, even a write asked for before it', () async {
      final cache = cacheOf();
      await cache.write(host, path, pic);
      unawaited(cache.write(host, '$path.2', pic));
      await cache.clear();
      expect(files(), isEmpty);
      expect(await cache.read(host, path), isNull);
    });

    test('past its size, the least recently drawn goes first', () async {
      final cache = cacheOf(maxBytes: 10);
      await cache.write(host, 'a', pic);
      await cache.write(host, 'b', pic);
      final [first, second] = files()
        ..sort(
          (x, y) => x.statSync().modified.compareTo(y.statSync().modified),
        );
      final now = DateTime.now();
      first.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
      second.setLastModifiedSync(now.subtract(const Duration(hours: 1)));

      // Drawing one makes it the newest, whichever was saved first.
      final drawn = (await cache.read(host, 'a')) != null ? 'a' : 'b';
      await cache.write(host, 'c', pic);
      expect(files(), hasLength(2));
      expect(await cache.read(host, drawn), pic);
      expect(await cache.read(host, 'c'), pic);
    });

    test('a picture not drawn for a month goes', () async {
      await cacheOf().write(host, path, pic);
      files().single.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 31)),
      );
      // The next run sweeps before it reads.
      expect(await cacheOf().read(host, path), isNull);
      expect(files(), isEmpty);
    });

    test('a half-written file from a killed run is swept', () async {
      root.createSync(recursive: true);
      File('${root.path}/abc.part').writeAsBytesSync(pic);
      await cacheOf().read(host, path);
      expect(files(), isEmpty);
    });
  });

  group('MediaStore on disk', () {
    test('the next run draws a fetched picture without fetching', () async {
      final disk = cacheOf();
      final first = MediaStore(maxEntries: 8, disk: disk);
      expect(await first.load(path, () async => pic, origin: host), pic);
      // The save runs behind the load; a read queues after it.
      await disk.read(host, path);

      final next = MediaStore(maxEntries: 8, disk: cacheOf());
      var fetched = 0;
      final bytes = await next.load(path, () async {
        fetched++;
        return null;
      }, origin: host);
      expect(bytes, pic);
      expect(fetched, 0);
      expect(next[path]!.status, MediaStatus.success);
    });

    test('an upload is saved too', () async {
      final disk = cacheOf();
      MediaStore(maxEntries: 8, disk: disk).put(path, pic, origin: host);
      expect(await disk.read(host, path), pic);
    });

    test('a failed fetch saves nothing', () async {
      final disk = cacheOf();
      final store = MediaStore(maxEntries: 8, disk: disk);
      expect(await store.load(path, () async => null, origin: host), isNull);
      expect(await disk.read(host, path), isNull);
    });

    test('without a host nothing touches the disk', () async {
      final disk = cacheOf();
      final store = MediaStore(maxEntries: 8, disk: disk);
      await store.load(path, () async => pic);
      store.put('other', pic);
      await disk.read(host, path);
      expect(files(), isEmpty);
    });

    test('clear empties the disk as well', () async {
      final disk = cacheOf();
      final store = MediaStore(maxEntries: 8, disk: disk);
      await store.load(path, () async => pic, origin: host);
      await store.clear();
      expect(files(), isEmpty);
    });
  });
}
