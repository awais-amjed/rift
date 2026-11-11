part of 'attachment_repository.dart';

/// Reading a big file where a player wants it, as it plays.
mixin _StreamReaderMixin on _StreamDownloadMixin {
  /// [attachment], read from [bucket] at any point as it is wanted
  /// ([ChunkedBlobReader]): what a chat video plays from. Null for a file
  /// that cannot be read that way — sealed in one piece, which opens only
  /// whole, or sent unencrypted, whose digest checks only once all of it has
  /// come — or one claiming a chunk size out of range.
  BlobReader? readerFor({
    required String baseUrl,
    required String anonKey,
    required BearerToken token,
    required String bucket,
    required Attachment attachment,
  }) {
    final chunk = attachment.chunkSize;
    if (!attachment.isEncrypted || chunk == null) return null;
    if (!ChunkedLayout.readable(plainSize: attachment.size, chunkSize: chunk)) {
      return null;
    }
    final layout = ChunkedLayout(plainSize: attachment.size, chunkSize: chunk);
    final uri = StorageRest.authenticated(
      baseUrl,
      bucket,
      attachment.storagePath,
    );
    final key = CryptoRepository.fromBase64(attachment.keyB64);
    final prefix = CryptoRepository.fromBase64(attachment.nonceB64);
    final span = _span(layout);
    Stream<Uint8List> fetch(int from) =>
        _openedFrom(uri, anonKey, token, layout, key, prefix, from, span);
    return ChunkedBlobReader(layout: layout, fetch: fetch);
  }

  /// Chunks [from] on, opened as they arrive, a span at a time: one request
  /// for a span of chunks, the next only once those are through. The first
  /// span is a quarter of [span] (at least 2), each after it twice the last
  /// up to [span]: a read here and there (a demuxer's look at the middle of
  /// the file) costs a small request, and a run being played soon asks for
  /// spans big enough to pay for a request's start. A request
  /// left open and unread is no limit on what arrives — the system keeps
  /// taking the body into its socket buffers, tens of megabytes on a fast
  /// link — so a span is what bounds how far a paused video runs ahead.
  ///
  /// A span that drops is taken up again from its next chunk, as often as it
  /// keeps getting further.
  Stream<Uint8List> _openedFrom(
    Uri uri,
    String anonKey,
    BearerToken token,
    ChunkedLayout layout,
    Uint8List key,
    Uint8List prefix,
    int from,
    int span,
  ) async* {
    var next = from;
    var attempt = 1;
    var size = (span ~/ 4).clamp(2, span);
    while (next < layout.chunkCount) {
      final abort = Completer<void>();
      final reached = next;
      final end = math.min(layout.chunkCount, next + size);
      try {
        final body = await _bodyFrom(
          uri,
          anonKey,
          token,
          layout.sealedOffset(next),
          until: layout.sealedOffset(end - 1) + layout.sealedLength(end - 1),
          abort: abort.future,
        );
        await for (final sealed in fixedChunks(
          body,
          layout.chunkSize + ChunkedLayout.tagLength,
        )) {
          if (sealed.isEmpty) continue;
          if (next >= end) {
            throw const FormatException('More chunks than were asked for');
          }
          final plain = await _crypto.openChunk(
            sealed: sealed,
            key: key,
            noncePrefix: prefix,
            index: next,
            last: layout.isLast(next),
          );
          next++;
          yield plain;
        }
        if (next != end) throw const FormatException('The file ends early');
        attempt = 1;
        size = math.min(span, size * 2);
      } catch (e) {
        if (next > reached) attempt = 1;
        if (!await _waitToRetry(e, attempt++)) rethrow;
      } finally {
        // Ends the request when the reader stops listening, even before
        // its body was read.
        if (!abort.isCompleted) abort.complete();
      }
    }
  }

  /// Chunks to a request: more for a bigger file, since a server whose
  /// Storage still hashes the whole file before answering each one
  /// (`STORAGE_FILE_ETAG_ALGORITHM` left at md5) takes longer to start the
  /// bigger the file; 8 to 32 of them.
  static int _span(ChunkedLayout layout) =>
      (layout.chunkCount ~/ 32).clamp(8, 32);
}
