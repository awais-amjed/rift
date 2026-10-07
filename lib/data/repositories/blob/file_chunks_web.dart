import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

import 'fixed_chunks.dart';

/// [file] as [size]-byte chunks, the last one whatever is left, re-cut from
/// a stream of the browser's file.
///
/// Not `XFile.openRead`: on the web it reads every byte into one buffer
/// before handing any over, so a big file sat whole in the tab's memory, and
/// past about 2 GB could not be read at all. Asked for a range, it fetches
/// the whole file again first, so reading in ranges copied it once per chunk.
/// Fetching the file's blob URL streams it instead, measured Oct 7 in Chrome
/// at 2 MB a piece and 200 MB in a quarter of a second.
Stream<Uint8List> fileChunks(XFile file, int size) =>
    fixedChunks(_read(file.path), size);

Stream<Uint8List> _read(String url) async* {
  final response = await web.window.fetch(url.toJS).toDart;
  final body = response.body;
  if (body == null) return;
  final reader = body.getReader() as web.ReadableStreamDefaultReader;
  try {
    while (true) {
      final piece = await reader.read().toDart;
      if (piece.done) break;
      yield (piece.value! as JSUint8Array).toDart;
    }
  } finally {
    reader.releaseLock();
  }
}
