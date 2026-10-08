import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/media_entry.dart';
import 'package:rift/logic/cubits/media/media_cubit.dart';
import 'package:rift/logic/services/media_store.dart';

/// The one copy of every fetched picture, and the cubit widgets read it
/// through. What broke before: each widget held its own copy, so one failed
/// download left that spot on initials while the picture sat in memory.
void main() {
  final pic = Uint8List.fromList([1, 2, 3]);

  group('MediaStore', () {
    test('two callers share one fetch', () async {
      final store = MediaStore(maxEntries: 10);
      var calls = 0;
      final gate = Completer<Uint8List?>();
      Future<Uint8List?> fetch() {
        calls++;
        return gate.future;
      }

      final a = store.load('p', fetch);
      final b = store.load('p', fetch);
      expect(store['p']!.status, MediaStatus.loading);
      gate.complete(pic);
      expect(await a, pic);
      expect(await b, pic);
      expect(calls, 1);
      expect(store['p'], MediaEntry.success(pic));
    });

    test('a failure is held, and asking again fetches again', () async {
      final store = MediaStore(maxEntries: 10);
      expect(await store.load('p', () async => null), isNull);
      expect(store['p']!.status, MediaStatus.failure);
      expect(await store.load('p', () async => pic), pic);
      expect(store['p']!.bytes, pic);
    });

    test('a fetch that throws is a failure, not a crash', () async {
      final store = MediaStore(maxEntries: 10);
      expect(await store.load('p', () => throw StateError('x')), isNull);
      expect(store['p']!.status, MediaStatus.failure);
    });

    test('removed while on its way, it does not come back', () async {
      // A deleted message's plaintext, or a wiped vault's.
      final store = MediaStore(maxEntries: 10);
      final gate = Completer<Uint8List?>();
      final load = store.load('p', () => gate.future);
      final joined = store.load('p', () async => pic);
      store.remove('p');
      gate.complete(pic);
      expect(await load, isNull);
      expect(await joined, isNull);
      expect(store['p'], isNull);

      final again = Completer<Uint8List?>();
      final second = store.load('q', () => again.future);
      store.clear();
      again.complete(pic);
      expect(await second, isNull);
      expect(store['q'], isNull);
    });

    test('evicts the oldest and says so', () async {
      final store = MediaStore(maxEntries: 2);
      final changed = <String>[];
      store.changes.listen(changed.add);
      store.put('a', pic);
      store.put('b', pic);
      store.put('c', pic);
      await Future<void>.delayed(Duration.zero);
      expect(store['a'], isNull);
      expect(store['c'], isNotNull);
      expect(changed, containsAllInOrder(['a', 'b', 'c', 'a']));
    });
  });

  group('MediaCubit', () {
    test('every reader sees a picture another one fetched', () async {
      final images = MediaStore(maxEntries: 10);
      final cubit = MediaCubit(
        images: images,
        attachments: MediaStore(maxEntries: 10),
      );
      cubit.want(MediaKind.image, 'p', () => images.load('p', () async => pic));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.bytes(MediaKind.image, 'p'), pic);
      await cubit.close();
    });

    test('starts with what the store already holds', () async {
      final images = MediaStore(maxEntries: 10)..put('p', pic);
      final cubit = MediaCubit(
        images: images,
        attachments: MediaStore(maxEntries: 10),
      );
      expect(cubit.state.bytes(MediaKind.image, 'p'), pic);
      await cubit.close();
    });

    test('a failed fetch is tried again on its own', () async {
      final images = MediaStore(maxEntries: 10);
      final cubit = MediaCubit(
        images: images,
        attachments: MediaStore(maxEntries: 10),
        retryAfter: const [Duration(milliseconds: 10)],
      );
      var calls = 0;
      cubit.want(
        MediaKind.image,
        'p',
        () => images.load('p', () async => ++calls == 1 ? null : pic),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        cubit.state.entry(MediaKind.image, 'p')!.status,
        MediaStatus.failure,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 2);
      expect(cubit.state.bytes(MediaKind.image, 'p'), pic);
      await cubit.close();
    });

    test('a picture already held is not fetched again', () async {
      final images = MediaStore(maxEntries: 10)..put('p', pic);
      final cubit = MediaCubit(
        images: images,
        attachments: MediaStore(maxEntries: 10),
      );
      var calls = 0;
      cubit.want(MediaKind.image, 'p', () async {
        calls++;
        return pic;
      });
      expect(calls, 0);
      await cubit.close();
    });
  });
}
