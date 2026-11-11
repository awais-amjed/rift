import 'dart:math' as math;
import 'dart:typed_data';

/// A file read at any point, as a player reads one: a demuxer jumps to the
/// index at the end of an MP4, then back to the start, then wherever a seek
/// lands.
///
/// What plays a chat video reads it through one of these, so a big one is
/// fetched as it plays rather than whole first ([ChunkedBlobReader]), and a
/// small one already in memory is read where it lies ([MemoryBlobReader]).
abstract class BlobReader {
  /// The file's size in bytes.
  int get length;

  /// Up to [max] bytes from [offset] on. Fewer when the file or a piece of
  /// it ends first, so a caller wanting more asks again from where this
  /// stopped; empty only at the end. Throws when the bytes cannot be had.
  Future<Uint8List> read(int offset, int max);

  /// Lets go of what it holds and stops fetching. A read after this throws.
  Future<void> close();
}

extension BlobReading on BlobReader {
  /// [length] bytes from [offset], or fewer only where the file ends:
  /// [BlobReader.read] asked again across the pieces it stops at.
  Future<Uint8List> readFully(int offset, int length) async {
    final first = await read(offset, length);
    if (first.length == length || first.isEmpty) return first;
    final all = BytesBuilder(copy: false)..add(first);
    while (all.length < length) {
      final more = await read(offset + all.length, length - all.length);
      if (more.isEmpty) break;
      all.add(more);
    }
    return all.takeBytes();
  }
}

/// A file already in memory.
class MemoryBlobReader implements BlobReader {
  final Uint8List _bytes;

  MemoryBlobReader(this._bytes);

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int max) async {
    if (offset < 0) throw RangeError.value(offset, 'offset');
    final from = math.min(offset, _bytes.length);
    final to = math.min(_bytes.length, from + math.max(0, max).toInt());
    return Uint8List.sublistView(_bytes, from, to);
  }

  @override
  Future<void> close() async {}
}
