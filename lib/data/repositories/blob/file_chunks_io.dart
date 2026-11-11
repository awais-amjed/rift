import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'blob_reader.dart';
import 'fixed_chunks.dart';
import 'stream_spans.dart';

/// [file] as [size]-byte chunks, the last one whatever is left. A file held
/// in memory rather than on disk is cut from its stream.
Stream<Uint8List> fileChunks(XFile file, int size) async* {
  if (file.path.isEmpty) {
    yield* fixedChunks(file.openRead(), size);
    return;
  }
  final handle = await File(file.path).open();
  try {
    var yielded = false;
    while (true) {
      final chunk = await handle.read(size);
      if (chunk.isEmpty && yielded) break;
      yielded = true;
      yield chunk;
      if (chunk.length < size) break;
    }
  } finally {
    await handle.close();
  }
}

/// [file] read by span, forward only: [read] [length] bytes from [offset],
/// fewer where it ends. Straight off the disk where it has a path.
Future<
  ({
    Future<Uint8List> Function(int offset, int length) read,
    Future<void> Function() close,
  })
>
fileSpans(XFile file) async {
  if (file.path.isEmpty) {
    final spans = StreamSpans(file.openRead().map(Uint8List.fromList));
    return (read: spans.read, close: spans.close);
  }
  final handle = await File(file.path).open();
  Future<Uint8List> read(int offset, int length) async {
    await handle.setPosition(offset);
    return handle.read(length);
  }

  return (read: read, close: handle.close);
}

/// [file] read at any point, as a player reads one, straight off the disk;
/// null for a file with no path. What a video's poster is made from when it
/// is too big to have been read into memory.
BlobReader? fileBlobReader(XFile file, int size) =>
    file.path.isEmpty ? null : _FileBlobReader(file.path, size);

class _FileBlobReader implements BlobReader {
  final String _path;
  @override
  final int length;
  RandomAccessFile? _handle;

  /// One read at a time: a [RandomAccessFile] refuses a second while one is
  /// under way, and a player may ask in two places at once.
  Future<void> _last = Future.value();

  _FileBlobReader(this._path, this.length);

  @override
  Future<Uint8List> read(int offset, int max) {
    if (offset < 0) throw RangeError.value(offset, 'offset');
    final done = _last.then((_) async {
      final handle = _handle ??= await File(_path).open();
      await handle.setPosition(offset);
      return handle.read(max);
    });
    _last = done.then((_) {}, onError: (_) {});
    return done;
  }

  @override
  Future<void> close() async {
    await _last;
    await _handle?.close();
    _handle = null;
  }
}
