import 'package:equatable/equatable.dart';

/// Where each sealed chunk of a file sealed a chunk at a time sits.
///
/// The file is cut into [chunkSize]-byte pieces, the last one shorter (or, for
/// an empty file, the only one and empty), and each is sealed with a 16-byte
/// tag after it. So everything about the sealed bytes follows from the two
/// numbers the attachment already carries — its plaintext [plainSize] and its
/// [chunkSize] — and nothing about the layout has to be written into the blob.
class ChunkedLayout extends Equatable {
  /// AES-GCM's tag, after every chunk.
  static const int tagLength = 16;

  /// The range a chunk size has to fall in to be read. This client seals
  /// 1 MiB chunks; the bounds leave room for another to choose differently.
  /// The size comes from the sender, and a reader holds a whole chunk before
  /// it can open it, so one claiming a gigabyte would have a phone hold the
  /// file in memory, and one of zero would have no chunks at all.
  static const int smallestChunk = 4 << 10;
  static const int largestChunk = 16 << 20;

  /// Whether a file of [plainSize] bytes in chunks of [chunkSize] is one this
  /// client will read.
  static bool readable({required int plainSize, required int chunkSize}) =>
      plainSize >= 0 && chunkSize >= smallestChunk && chunkSize <= largestChunk;

  final int plainSize;
  final int chunkSize;

  const ChunkedLayout({required this.plainSize, required this.chunkSize})
    : assert(chunkSize > 0);

  /// At least one: an empty file is one empty chunk, so it still has a last
  /// chunk to say where it ends.
  int get chunkCount =>
      plainSize == 0 ? 1 : (plainSize + chunkSize - 1) ~/ chunkSize;

  int get sealedSize => plainSize + tagLength * chunkCount;

  bool isLast(int index) => index == chunkCount - 1;

  /// Plaintext bytes in chunk [index].
  int plainLength(int index) =>
      isLast(index) ? plainSize - chunkSize * index : chunkSize;

  /// Where chunk [index] starts in the plaintext.
  int plainOffset(int index) => chunkSize * index;

  /// Where chunk [index] starts in the sealed blob.
  int sealedOffset(int index) => (chunkSize + tagLength) * index;

  int sealedLength(int index) => plainLength(index) + tagLength;

  /// The chunk the sealed byte at [offset] belongs to.
  int chunkAtSealed(int offset) => offset ~/ (chunkSize + tagLength);

  @override
  List<Object?> get props => [plainSize, chunkSize];
}
