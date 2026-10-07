part of 'attachment_repository.dart';

/// The bearer token for a streamed transfer, asked for before every request
/// rather than once: a big file can take longer to send than a session lasts.
/// [refresh] is asked after a request came back unauthorized, and must sign
/// in again rather than hand back the token that just failed.
typedef BearerToken = Future<String> Function({bool refresh});

/// How far a transfer has got: [done] of [total] bytes.
typedef TransferProgress = void Function(int done, int total);

/// Sending and fetching a big file a chunk at a time, so that no copy of it
/// has to fit in memory on either end.
///
/// **Sealing.** The file is cut into [chunkSize] pieces, each sealed under
/// STREAM ([CryptoRepository.sealChunk]) with its position and a last-chunk
/// flag in its nonce, so the server can neither reorder, drop nor cut off
/// chunks. A file sent unencrypted is hashed as it goes instead.
///
/// **Uploading** goes over tus ([TusClient]), [_chunksPerRequest] chunks to a
/// request. A request that fails is sent again from wherever the server says
/// it got to, up to [_attempts] times, so a dropped connection costs a few
/// megabytes rather than the file.
///
/// **Downloading** reads one response as it arrives, opens each chunk as it
/// completes, and hands it to a [BlobSink], which keeps it out of sight until
/// the whole file has checked out.
mixin _AttachmentStreamMixin {
  CryptoRepository get _crypto;
  http.Client get _http;

  /// Implemented by [AttachmentRepository]: a blob fetched whole, opened.
  Future<Uint8List> open({
    required Uint8List ciphertext,
    required String keyB64,
    required String nonceB64,
    String? sha256B64,
    int? chunkSize,
  });

  /// Plaintext bytes in a chunk. Small enough that holding a request's worth
  /// is nothing, big enough that the work per chunk (a bridge call, a key
  /// schedule) is lost in the noise.
  static const int chunkSize = 1 << 20;

  /// Chunks per tus request: about 16 MB a request. Measured Oct 7 against
  /// the local stack, 192 MB took 2.0 s in 8 MB requests and 1.55 s in 32 MB
  /// ones; 16 is most of that gain for half the memory, which a phone feels.
  static const int _chunksPerRequest = 16;

  /// Tries at one request before the transfer is given up on.
  static const int _attempts = 5;

  // ── Upload ────────────────────────────────────────────────

  /// Seal [file] ([length] bytes) a chunk at a time and send it to [bucket]
  /// under [scopePrefix], or send it as it is when [plain]. On success `data`
  /// is an [UploadedBlob].
  Future<APIResponse> uploadStreamed({
    required String baseUrl,
    required String anonKey,
    required BearerToken token,
    required String bucket,
    required String scopePrefix,
    required XFile file,
    required int length,
    bool plain = false,
    TransferProgress? onProgress,
  }) async {
    final tus = TusClient(_http);
    final layout = ChunkedLayout(plainSize: length, chunkSize: chunkSize);
    final key = plain ? null : _crypto.generateFileKey();
    final prefix = plain ? null : _crypto.generateChunkNoncePrefix();
    final digest = plain ? _crypto.startDigest() : null;
    final total = plain ? length : layout.sealedSize;
    final path = AttachmentRepository.buildPath(scopePrefix);
    Uri? upload;
    try {
      upload = await _authorized(
        anonKey,
        token,
        (auth) => tus.create(
          baseUrl: baseUrl,
          auth: auth,
          bucket: bucket,
          objectName: path,
          length: total,
        ),
      );

      var offset = 0;
      var index = 0;
      var read = 0;
      final batch = BytesBuilder(copy: false);
      Future<void> send() async {
        final body = batch.takeBytes();
        if (body.isEmpty) return;
        offset = await _sendPiece(tus, anonKey, token, upload!, offset, body);
        onProgress?.call(offset, total);
      }

      await for (final chunk in fileChunks(file, chunkSize)) {
        read += chunk.length;
        // A file that grew since it was picked would put chunks after the one
        // sealed as the last; stop before sending a stream that cannot open.
        if (index >= layout.chunkCount) break;
        if (digest != null) {
          await digest.add(chunk);
          batch.add(chunk);
        } else {
          batch.add(
            await _crypto.sealChunk(
              data: chunk,
              key: key!,
              noncePrefix: prefix!,
              index: index,
              last: layout.isLast(index),
            ),
          );
        }
        index++;
        if (batch.length >= chunkSize * _chunksPerRequest) await send();
      }
      if (read != length || index != layout.chunkCount) {
        throw StorageRefused(
          APIResponse.error('The file changed while it was being sent.'),
        );
      }
      await send();

      final UploadedBlob uploaded = (
        path: path,
        keyB64: key == null ? '' : CryptoRepository.toBase64(key),
        nonceB64: prefix == null ? '' : CryptoRepository.toBase64(prefix),
        sha256B64: digest == null
            ? null
            : CryptoRepository.toBase64(await digest.close()),
        chunkSize: plain ? null : chunkSize,
      );
      return APIResponse.success(uploaded);
    } on StorageRefused catch (e) {
      await _cancel(tus, anonKey, token, upload);
      return e.response;
    } catch (e) {
      await _cancel(tus, anonKey, token, upload);
      return APIResponse.error(e);
    }
  }

  /// Send [body] at [offset], again from where the server got to if it
  /// fails, and answer the offset after it.
  Future<int> _sendPiece(
    TusClient tus,
    String anonKey,
    BearerToken token,
    Uri upload,
    int offset,
    Uint8List body,
  ) async {
    var held = 0;
    for (var attempt = 1; ; attempt++) {
      try {
        final at = await _authorized(
          anonKey,
          token,
          (auth) => tus.patch(
            upload: upload,
            auth: auth,
            offset: offset + held,
            body: Uint8List.sublistView(body, held),
          ),
        );
        if (at >= offset + body.length) return at;
        held = at - offset;
      } catch (e) {
        if (!_worthRetrying(e) || attempt >= _attempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
        try {
          final at = await _authorized(
            anonKey,
            token,
            (auth) => tus.offset(upload: upload, auth: auth),
          );
          held = (at - offset).clamp(0, body.length);
        } catch (_) {
          // Still unreachable; the next attempt finds out.
        }
      }
    }
  }

  Future<void> _cancel(
    TusClient tus,
    String anonKey,
    BearerToken token,
    Uri? upload,
  ) async {
    if (upload == null) return;
    try {
      await tus.cancel(
        upload: upload,
        auth: StorageRest.headers(anonKey, await token()),
      );
    } catch (_) {}
  }

  // ── Download ──────────────────────────────────────────────

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
        if (!_worthRetrying(e) || attempt >= _attempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
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

  // ── Shared ────────────────────────────────────────────────

  /// [call] with the current token, and once more with a fresh one if the
  /// server says the session has expired.
  Future<T> _authorized<T>(
    String anonKey,
    BearerToken token,
    Future<T> Function(Map<String, String> auth) call,
  ) async {
    try {
      return await call(StorageRest.headers(anonKey, await token()));
    } on StorageRefused catch (e) {
      if (!e.sessionExpired) rethrow;
      return call(StorageRest.headers(anonKey, await token(refresh: true)));
    }
  }

  /// A dropped connection, a stall, or a server having trouble — rather than
  /// an answer another try would get again, or a chunk that would not open.
  static bool _worthRetrying(Object error) => switch (error) {
    StorageRefused() => error.retryable,
    http.ClientException() || TimeoutException() => true,
    _ => false,
  };

  static Duration _backoff(int attempt) =>
      Duration(seconds: 1 << (attempt - 1));
}
