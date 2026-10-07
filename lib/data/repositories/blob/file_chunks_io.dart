import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'fixed_chunks.dart';

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
