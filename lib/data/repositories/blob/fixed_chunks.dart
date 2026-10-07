import 'dart:typed_data';

/// [source] re-cut into pieces of exactly [size] bytes, the last one whatever
/// is left over.
///
/// A file read from disk or a browser arrives in pieces of whatever size the
/// platform likes — 64 KB from `dart:io`, something else on the web — and a
/// file sealed a chunk at a time needs them cut where the layout says. An
/// empty [source] still yields one empty piece, because an empty file is one
/// empty chunk (see `ChunkedLayout.chunkCount`).
Stream<Uint8List> fixedChunks(Stream<List<int>> source, int size) async* {
  final pending = BytesBuilder(copy: false);
  var yielded = false;
  await for (final piece in source) {
    var data = piece is Uint8List ? piece : Uint8List.fromList(piece);
    while (pending.length + data.length >= size) {
      final take = size - pending.length;
      pending.add(Uint8List.sublistView(data, 0, take));
      yield pending.takeBytes();
      yielded = true;
      data = Uint8List.sublistView(data, take);
    }
    if (data.isNotEmpty) pending.add(Uint8List.fromList(data));
  }
  if (pending.isNotEmpty || !yielded) yield pending.takeBytes();
}
