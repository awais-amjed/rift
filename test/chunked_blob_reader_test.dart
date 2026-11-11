import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chunked_layout.dart';
import 'package:rift/data/repositories/blob/blob_reader.dart';
import 'package:rift/data/repositories/blob/chunked_blob_reader.dart';

/// A file of [count] chunks of [size] bytes and a short last one, whose
/// every byte is its chunk's index: what was read says where it came from.
class _Fake {
  static const int size = 4096;
  final int count;
  final ChunkedLayout layout;
  final List<int> starts = [];

  /// Chunks handed over, across every run.
  int produced = 0;

  /// When set, the run fails before handing over this chunk.
  int? failAt;

  _Fake(this.count)
    : layout = ChunkedLayout(
        plainSize: size * (count - 1) + 100,
        chunkSize: size,
      );

  Uint8List chunk(int i) =>
      Uint8List(layout.plainLength(i))..fillRange(0, layout.plainLength(i), i);

  Stream<Uint8List> fetch(int from) async* {
    starts.add(from);
    for (var i = from; i < count; i++) {
      await Future<void>.delayed(Duration.zero);
      if (i == failAt) throw const FormatException('broken');
      produced++;
      yield chunk(i);
    }
  }

  ChunkedBlobReader reader({
    int keep = 48,
    int ahead = 4,
    int reach = 3,
    int runs = 3,
  }) => ChunkedBlobReader(
    layout: layout,
    fetch: fetch,
    keep: keep,
    ahead: ahead,
    reach: reach,
    runs: runs,
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const size = _Fake.size;

  test('a memory reader reads where asked and stops at the end', () async {
    final reader = MemoryBlobReader(Uint8List.fromList([1, 2, 3, 4, 5]));
    expect(await reader.read(1, 3), [2, 3, 4]);
    expect(await reader.read(3, 10), [4, 5]);
    expect(await reader.read(5, 10), isEmpty);
  });

  test('reading in order is one run', () async {
    final fake = _Fake(10);
    final reader = fake.reader(ahead: 20);
    for (var offset = 0; offset < reader.length;) {
      final got = await reader.read(offset, 1000);
      expect(got, everyElement(offset ~/ size));
      offset += got.length;
    }
    expect(fake.starts, [0]);
    expect(await reader.read(reader.length, 10), isEmpty);
  });

  test('a read stops at the end of its chunk', () async {
    final fake = _Fake(4);
    final reader = fake.reader();
    final got = await reader.read(size - 10, 100);
    expect(got.length, 10);
    expect(got, everyElement(0));
    expect(await reader.read(size, 5), everyElement(1));
    expect(await reader.read(size * 3, 1000), hasLength(100));
  });

  test(
    'a read near the run waits for it; one far from it starts another',
    () async {
      final fake = _Fake(40);
      final reader = fake.reader(ahead: 30, reach: 3);
      await reader.read(0, 1);
      // Within reach of the run: no new request.
      expect(await reader.read(size * 3, 1), [3]);
      expect(fake.starts, [0]);
      // The index at the end of an MP4.
      expect(await reader.read(size * 39, 1), [39]);
      expect(fake.starts, [0, 39]);
      // Back to the start, behind that run and out of memory? Held still.
      expect(await reader.read(0, 1), [0]);
      expect(fake.starts, [0, 39]);
      // Behind the run and never fetched: a run from there.
      expect(await reader.read(size * 20, 1), [20]);
      expect(fake.starts, [0, 39, 20]);
    },
  );

  test(
    'a run pauses ahead of the last read and goes on when it moves',
    () async {
      final fake = _Fake(40);
      final reader = fake.reader(ahead: 4);
      await reader.read(0, 1);
      await _settle();
      expect(reader.running.single.paused, isTrue);
      expect(reader.running.single.next, 5);
      expect(fake.produced, lessThanOrEqualTo(6));

      await reader.read(size * 3, 1);
      await _settle();
      expect(reader.running.single.next, 8);
      expect(reader.running.single.paused, isTrue);
      expect(fake.starts, [0]);
    },
  );

  test('only the last few chunks stay in memory', () async {
    final fake = _Fake(20);
    final reader = fake.reader(keep: 6, ahead: 1, reach: 2);
    for (var i = 0; i < 12; i++) {
      await reader.read(size * i, 1);
    }
    expect(reader.held.length, lessThanOrEqualTo(6));
    expect(reader.held, contains(11));
    expect(reader.held, isNot(contains(0)));
  });

  test(
    'a failed run fails what waits on it, and the next read tries again',
    () async {
      final fake = _Fake(10)..failAt = 2;
      final reader = fake.reader(ahead: 20);
      await expectLater(reader.read(size * 2, 1), throwsFormatException);
      fake.failAt = null;
      expect(await reader.read(size * 2, 1), [2]);
      expect(fake.starts, [2, 2]);
    },
  );

  test('reads in two places at once each get theirs, and each run pauses', () async {
    final fake = _Fake(60);
    final reader = fake.reader(ahead: 4, reach: 3);
    // The start, and at the same moment the index at the end.
    final start = reader.read(size * 2, 1);
    final end = reader.read(size * 58, 1);
    expect(await start, [2]);
    expect(await end, [58]);
    // Back to where the start was going: that run still serves it.
    expect(await reader.read(size * 3, 1), [3]);
    expect(fake.starts, [2, 58]);
    await _settle();
    // Neither runs on to the end of the file by itself.
    expect(fake.produced, lessThan(20));
    for (final run in reader.running) {
      expect(run.paused || run.next >= 60, isTrue);
    }
  });

  test('a run that is replaced never strands a read waiting on it', () async {
    final fake = _Fake(60);
    final reader = fake.reader(ahead: 4, reach: 3, runs: 1);
    final near = reader.read(size * 1, 1);
    final far = reader.read(size * 40, 1);
    final farther = reader.read(size * 50, 1);
    expect(await near, [1]);
    expect(await far, [40]);
    expect(await farther, [50]);
    await _settle();
    expect(fake.produced, lessThan(30));
  });

  test('closing fails what waits and refuses what comes after', () async {
    final fake = _Fake(10);
    final reader = fake.reader();
    final waiting = expectLater(reader.read(size * 2, 1), throwsStateError);
    await reader.close();
    await waiting;
    await expectLater(reader.read(0, 1), throwsStateError);
  });
}
