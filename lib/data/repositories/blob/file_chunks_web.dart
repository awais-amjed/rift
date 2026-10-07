import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'fixed_chunks.dart';

/// [file] as [size]-byte chunks, the last one whatever is left, re-cut from
/// the browser's own pieces.
Stream<Uint8List> fileChunks(XFile file, int size) =>
    fixedChunks(file.openRead(), size);
