import 'dart:typed_data';

/// Where a downloaded attachment's bytes go as they are opened: memory for
/// one drawn in the chat, a file for one being saved.
///
/// A piece is handed over only once it has been opened and checked, but a
/// file that fails later — a chunk changed, a digest that does not match at
/// the end — has already handed over its earlier pieces. So a sink must keep
/// what it is given out of sight until [close], and [abort] must leave
/// nothing behind.
abstract interface class BlobSink {
  Future<void> add(Uint8List data);

  /// Everything arrived and checked out: make it the result.
  Future<void> close();

  /// It did not: throw away whatever was added.
  Future<void> abort();
}

/// A [BlobSink] that keeps the bytes in memory, for an attachment drawn in
/// the chat (an image, a voice note), which has to be in memory to be drawn.
class MemoryBlobSink implements BlobSink {
  final _bytes = BytesBuilder(copy: false);
  Uint8List? _result;

  /// The whole file, once [close]d.
  Uint8List get bytes => _result ?? (throw StateError('Not closed'));

  @override
  Future<void> add(Uint8List data) async => _bytes.add(data);

  @override
  Future<void> close() async => _result = _bytes.takeBytes();

  @override
  Future<void> abort() async => _bytes.clear();
}
