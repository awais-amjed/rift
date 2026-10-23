part of 'attachment_repository.dart';

/// Fetching a big file as it arrives and opening it a chunk at a time.
mixin _StreamDownloadMixin on _AttachmentStreamMixin {
  /// Implemented by [AttachmentRepository]: a blob fetched whole, opened.
  Future<Uint8List> open({
    required Uint8List ciphertext,
    required String keyB64,
    required String nonceB64,
    String? sha256B64,
    int? chunkSize,
  });

  /// Fetch [attachment] from [bucket] and hand its bytes to [sink] as they
  /// are opened, then close it — or abort it, and answer why, when any of it
  /// fails to open.
  ///
  /// One GET, read as it arrives, rather than a request per span: Storage's
  /// file backend takes as long to start answering a `Range` request as to
  /// send a few hundred megabytes (measured Oct 7: 1.7 s per span against
  /// 3.9 s for a 650 MB file whole). A connection that drops partway is taken
  /// up again from the first byte not yet opened, which is the one place a
  /// range is worth its cost.
  ///
  /// A file sealed a chunk at a time is opened a chunk at a time. One sent
  /// unencrypted is hashed as it comes and checked at the end. One sealed in
  /// one piece, as every file was before chunking, can only be opened whole,
  /// so it is.
  Future<APIResponse> downloadTo({
    required String baseUrl,
    required String anonKey,
    required BearerToken token,
    required String bucket,
    required Attachment attachment,
    required BlobSink sink,
    TransferProgress? onProgress,
  }) async {
    final uri = StorageRest.authenticated(
      baseUrl,
      bucket,
      attachment.storagePath,
    );
    try {
      if (!attachment.isEncrypted) {
        await _downloadPlain(uri, anonKey, token, attachment, sink, onProgress);
      } else if (attachment.chunkSize case final chunk?) {
        await _downloadChunked(
          uri,
          anonKey,
          token,
          attachment,
          chunk,
          sink,
          onProgress,
        );
      } else {
        final whole = BytesBuilder(copy: false);
        await _readFrom(uri, anonKey, token, 0, (body) async {
          await for (final piece in body) {
            whole.add(piece);
          }
        });
        await sink.add(
          await open(
            ciphertext: whole.takeBytes(),
            keyB64: attachment.keyB64,
            nonceB64: attachment.nonceB64,
          ),
        );
        onProgress?.call(attachment.size, attachment.size);
      }
      await sink.close();
      return APIResponse.success(null);
    } on StorageRefused catch (e) {
      await sink.abort();
      return e.response;
    } catch (e) {
      await sink.abort();
      return APIResponse.error(e);
    }
  }

  Future<void> _downloadChunked(
    Uri uri,
    String anonKey,
    BearerToken token,
    Attachment attachment,
    int chunk,
    BlobSink sink,
    TransferProgress? onProgress,
  ) async {
    if (!ChunkedLayout.readable(plainSize: attachment.size, chunkSize: chunk)) {
      throw const FormatException('The file claims a chunk size out of range');
    }
    final layout = ChunkedLayout(plainSize: attachment.size, chunkSize: chunk);
    final key = CryptoRepository.fromBase64(attachment.keyB64);
    final prefix = CryptoRepository.fromBase64(attachment.nonceB64);
    var next = 0;
    await _readResuming(
      uri,
      anonKey,
      token,
      // Always from a chunk's start: a chunk only opens whole.
      () => layout.sealedOffset(next),
      (body) async {
        await for (final sealed in fixedChunks(
          body,
          chunk + ChunkedLayout.tagLength,
        )) {
          if (sealed.isEmpty) continue;
          if (next >= layout.chunkCount) {
            throw const FormatException('More chunks than the file has');
          }
          await sink.add(
            await _crypto.openChunk(
              sealed: sealed,
              key: key,
              noncePrefix: prefix,
              index: next,
              last: layout.isLast(next),
            ),
          );
          onProgress?.call(
            layout.plainOffset(next) + layout.plainLength(next),
            attachment.size,
          );
          next++;
        }
      },
    );
    // A file cut off after a whole chunk opens every chunk it has, and only
    // the missing last one would have said so.
    if (next != layout.chunkCount) {
      throw const FormatException('The file ends early');
    }
  }

  Future<void> _downloadPlain(
    Uri uri,
    String anonKey,
    BearerToken token,
    Attachment attachment,
    BlobSink sink,
    TransferProgress? onProgress,
  ) async {
    final digest = _crypto.startDigest();
    var received = 0;
    await _readResuming(uri, anonKey, token, () => received, (body) async {
      await for (final piece in body) {
        final bytes = piece is Uint8List ? piece : Uint8List.fromList(piece);
        await digest.add(bytes);
        await sink.add(bytes);
        received += bytes.length;
        onProgress?.call(received, attachment.size);
      }
    });
    final got = CryptoRepository.toBase64(await digest.close());
    if (received != attachment.size || got != attachment.sha256B64) {
      throw const FormatException('The file does not match its digest');
    }
  }

  /// [_readFrom] from wherever [from] says, again from there when the
  /// connection drops, up to [_attempts] times.
  Future<void> _readResuming(
    Uri uri,
    String anonKey,
    BearerToken token,
    int Function() from,
    Future<void> Function(Stream<List<int>> body) consume,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _readFrom(uri, anonKey, token, from(), consume);
      } catch (e) {
        if (!await _waitToRetry(e, attempt)) rethrow;
      }
    }
  }

  /// GET [uri] from byte [start] to the end and hand its body to [consume]
  /// as it arrives. A body that goes quiet for a minute is a dropped
  /// connection, whatever the socket thinks.
  Future<void> _readFrom(
    Uri uri,
    String anonKey,
    BearerToken token,
    int start,
    Future<void> Function(Stream<List<int>> body) consume,
  ) async {
    final response = await _authorized(anonKey, token, (auth) async {
      final request = http.Request('GET', uri)
        ..headers.addAll({...auth, if (start > 0) 'Range': 'bytes=$start-'});
      final streamed = await _http.send(request).timeout(StorageRest.timeout);
      if (streamed.statusCode >= 300) {
        final reply = await http.Response.fromStream(streamed);
        throw StorageRefused(
          StorageRest.refusal(reply, failed: 'Download failed')!,
          status: reply.statusCode,
        );
      }
      if (start > 0 && streamed.statusCode != 206) {
        throw const FormatException('The server ignored the range');
      }
      return streamed;
    });
    await consume(response.stream.timeout(const Duration(minutes: 1)));
  }
}
