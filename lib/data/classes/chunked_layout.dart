/// Where each sealed chunk of a file sealed a chunk at a time sits.
///
/// The file is cut into [chunkSize]-byte pieces, the last one shorter (or, for
/// an empty file, the only one and empty), and each is sealed with a 16-byte
/// tag after it. So everything about the sealed bytes follows from the two
/// numbers the attachment already carries — its plaintext [plainSize] and its
/// [chunkSize] — and nothing about the layout has to be written into the blob.
class ChunkedLayout {
  /// AES-GCM's tag, after every chunk.
  static const int tagLength = 16;

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
}
