import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/apis/soundboard_api.dart';
import 'package:rift/data/repositories/soundboard_repository.dart';
import 'package:rift/logic/services/media_disk_cache.dart';

/// A clip's path is the server's choice, and the clip cache used to build a
/// file name from it: `..\` climbed out of the folder on Windows.
void main() {
  const server = '766c2be5-08bf-4bbc-aff6-f7618be3e573';

  group('SoundboardApi.ownsPath', () {
    test('takes a path the app mints', () {
      expect(
        SoundboardApi.ownsPath(server, SoundboardRepository.buildPath(server)),
        isTrue,
      );
    });

    test('drops paths that climb, nest or belong elsewhere', () {
      for (final path in [
        '$server/..\\..\\..\\Users\\me\\file.txt',
        '$server/../other/x.audio',
        '$server/a/b.audio',
        '$server/..audio',
        '$server/.hidden',
        '$server/',
        'other-server/x.audio',
        '${server}x/x.audio',
        'x.audio',
      ]) {
        expect(SoundboardApi.ownsPath(server, path), isFalse, reason: path);
      }
    });
  });

  group('MediaDiskCache.fileNameFor', () {
    test('is a plain hex name whatever the path holds', () async {
      final name = await MediaDiskCache.fileNameFor(
        'https://a.example',
        '$server/..\\..\\evil',
      );
      expect(name, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test(
      'differs by host, so one server cannot stand in for another',
      () async {
        final path = '$server/abc.audio';
        expect(
          await MediaDiskCache.fileNameFor('https://a.example', path),
          isNot(await MediaDiskCache.fileNameFor('https://b.example', path)),
        );
      },
    );
  });
}
