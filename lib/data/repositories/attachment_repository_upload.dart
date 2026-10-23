part of 'attachment_repository.dart';

/// Sealing a big file a chunk at a time and sending it over tus.
mixin _StreamUploadMixin on _AttachmentStreamMixin {
  /// Plaintext bytes in a chunk. Small enough that holding a request's worth
  /// is nothing, big enough that the work per chunk (a bridge call, a key
  /// schedule) is lost in the noise.
  static const int chunkSize = 1 << 20;

  /// Chunks per tus request: about 16 MB a request. Measured Oct 7 against
  /// the local stack, 192 MB took 2.0 s in 8 MB requests and 1.55 s in 32 MB
  /// ones; 16 is most of that gain for half the memory, which a phone feels.
  static const int _chunksPerRequest = 16;

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
        if (!await _waitToRetry(e, attempt)) rethrow;
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
}
