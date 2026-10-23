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
/// **Sealing.** The file is cut into [_StreamUploadMixin.chunkSize] pieces,
/// each sealed under STREAM ([CryptoRepository.sealChunk]) with its position
/// and a last-chunk flag in its nonce, so the server can neither reorder,
/// drop nor cut off chunks. A file sent unencrypted is hashed as it goes
/// instead.
///
/// **Uploading** goes over tus ([TusClient]), a few chunks to a request. A
/// request that fails is sent again from wherever the server says it got to,
/// up to [_attempts] times, so a dropped connection costs a few megabytes
/// rather than the file.
///
/// **Downloading** reads one response as it arrives, opens each chunk as it
/// completes, and hands it to a [BlobSink], which keeps it out of sight until
/// the whole file has checked out.
///
/// The two directions are their own parts, `attachment_repository_upload.dart`
/// and `attachment_repository_download.dart`; this holds what both lean on.
mixin _AttachmentStreamMixin {
  CryptoRepository get _crypto;
  http.Client get _http;

  /// Tries at one request before the transfer is given up on.
  static const int _attempts = 5;

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

  /// Whether a request that failed with [error] on its [attempt]th try is
  /// worth another, after waiting a little longer each time.
  Future<bool> _waitToRetry(Object error, int attempt) async {
    if (!_worthRetrying(error) || attempt >= _attempts) return false;
    await Future<void>.delayed(_backoff(attempt));
    return true;
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
