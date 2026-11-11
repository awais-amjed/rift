import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

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
