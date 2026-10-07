import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chunked_layout.dart';
import 'package:rift/data/repositories/blob/fixed_chunks.dart';

void main() {
  group('ChunkedLayout', () {
    test('a file that fills its chunks exactly', () {
      const l = ChunkedLayout(plainSize: 30, chunkSize: 10);
      expect(l.chunkCount, 3);
      expect(l.sealedSize, 30 + 3 * 16);
      expect(l.plainLength(2), 10);
      expect(l.sealedOffset(2), 52);
      expect(l.isLast(2), isTrue);
      expect(l.chunkAtSealed(51), 1);
      expect(l.chunkAtSealed(52), 2);
    });

    test('a short last chunk', () {
      const l = ChunkedLayout(plainSize: 25, chunkSize: 10);
      expect(l.chunkCount, 3);
      expect(l.plainLength(2), 5);
      expect(l.sealedLength(2), 21);
      expect(l.sealedSize, 25 + 48);
    });

    // Still one chunk, so the file still has an end the server cannot move.
    test('an empty file is one empty chunk', () {
      const l = ChunkedLayout(plainSize: 0, chunkSize: 10);
      expect(l.chunkCount, 1);
      expect(l.plainLength(0), 0);
      expect(l.sealedSize, 16);
    });
  });

  group('fixedChunks', () {
    Stream<List<int>> pieces(List<int> sizes) async* {
      var n = 0;
      for (final size in sizes) {
        yield [for (var i = 0; i < size; i++) n++ & 0xff];
      }
    }

    Future<List<int>> lengths(Stream<List<int>> s, int size) async => [
      await for (final c in fixedChunks(s, size)) c.length,
    ];

    test('cuts uneven pieces at the chunk size', () async {
      expect(await lengths(pieces([3, 7, 1, 14]), 10), [10, 10, 5]);
    });

    test('keeps the bytes in order', () async {
      final all = BytesBuilder();
      await for (final c in fixedChunks(pieces([3, 7, 1, 14]), 4)) {
        all.add(c);
      }
      expect(all.takeBytes(), [for (var i = 0; i < 25; i++) i]);
    });

    test('a source that ends on a chunk boundary has no empty tail', () async {
      expect(await lengths(pieces([5, 5, 10]), 10), [10, 10]);
    });

    test('an empty source is one empty chunk', () async {
      expect(await lengths(pieces([]), 10), [0]);
    });
  });

  group('ChunkedLayout.readable', () {
    test('takes the size this client seals in', () {
      expect(
        ChunkedLayout.readable(plainSize: 650 << 20, chunkSize: 1 << 20),
        isTrue,
      );
    });

    test('refuses a sender\'s chunk size out of range', () {
      // A gigabyte a chunk would have the reader hold the file in memory.
      expect(
        ChunkedLayout.readable(plainSize: 1 << 30, chunkSize: 1 << 30),
        isFalse,
      );
      expect(ChunkedLayout.readable(plainSize: 10, chunkSize: 0), isFalse);
      expect(ChunkedLayout.readable(plainSize: 10, chunkSize: -1), isFalse);
      expect(
        ChunkedLayout.readable(plainSize: -1, chunkSize: 1 << 20),
        isFalse,
      );
    });
  });
}
