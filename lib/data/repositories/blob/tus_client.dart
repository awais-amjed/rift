import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../classes/api_response.dart';
import '../storage_rest.dart';

/// A refusal from Storage partway through a streamed transfer, carrying the
/// [APIResponse] the caller hands back — `token_expired` for a 401 or 403, so
/// the caller can sign in again and carry on.
class StorageRefused implements Exception {
  final APIResponse response;

  /// The HTTP status behind it, when there was one.
  final int? status;

  const StorageRefused(this.response, {this.status});

  bool get sessionExpired => response.errorCode == 'token_expired';

  /// Whether the same request could get a different answer: the server having
  /// trouble (5xx), a timeout or rate limit, or a tus offset that moved under
  /// us (409), which the next try reads back first.
  bool get retryable {
    final code = status;
    return code != null &&
        (code >= 500 || code == 408 || code == 409 || code == 429);
  }

  @override
  String toString() => response.error ?? 'Storage refused the request';
}

/// The parts of the tus protocol Storage speaks, for an upload sent in pieces.
///
/// Why tus rather than one long POST: a request body that is a stream is
/// something a browser will not send (fetch buffers it whole), so the web
/// could never upload a file bigger than its memory that way. Here every piece
/// is an ordinary request of a few megabytes, on every platform, and a piece
/// that fails is sent again from where the server says it got to rather than
/// starting the file over.
///
/// Storage serves it under `/storage/v1/upload/resumable` with the same keys
/// and policies as a plain upload; the bucket's size limit is checked against
/// `Upload-Length` before a byte is sent.
class TusClient {
  final http.Client _http;
  const TusClient(this._http);

  static const _version = {'Tus-Resumable': '1.0.0'};

  /// Starts an upload of [length] bytes to [objectName] in [bucket] and
  /// answers where its pieces go.
  ///
  /// The address is rebuilt on [baseUrl] from the id Storage hands back,
  /// rather than taken whole: Storage builds it from its own idea of its
  /// public address, which is not always the one this client reached it at.
  Future<Uri> create({
    required String baseUrl,
    required Map<String, String> auth,
    required String bucket,
    required String objectName,
    required int length,
  }) async {
    String meta(String key, String value) =>
        '$key ${base64Encode(utf8.encode(value))}';
    final response = await _http
        .post(
          Uri.parse('$baseUrl/storage/v1/upload/resumable'),
          headers: {
            ...auth,
            ..._version,
            'Upload-Length': '$length',
            'Upload-Metadata': [
              meta('bucketName', bucket),
              meta('objectName', objectName),
              meta('contentType', 'application/octet-stream'),
            ].join(','),
            'x-upsert': 'false',
          },
        )
        .timeout(StorageRest.timeout);
    _check(response, 'Upload failed');
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw StorageRefused(
        APIResponse.error('Upload failed — the server did not say where to.'),
      );
    }
    final id = Uri.parse(location).pathSegments.last;
    return Uri.parse('$baseUrl/storage/v1/upload/resumable/$id');
  }

  /// Sends [body] at [offset] and answers the offset the server is now at.
  Future<int> patch({
    required Uri upload,
    required Map<String, String> auth,
    required int offset,
    required Uint8List body,
  }) async {
    final response = await StorageRest.sendBytes(
      _http,
      'PATCH',
      upload,
      headers: {
        ...auth,
        ..._version,
        'Upload-Offset': '$offset',
        'Content-Type': 'application/offset+octet-stream',
      },
      body: body,
    ).timeout(pieceTimeout(body.length));
    _check(response, 'Upload failed');
    return int.tryParse(response.headers['upload-offset'] ?? '') ??
        offset + body.length;
  }

  /// How much of [upload] the server holds — where a piece that failed is
  /// sent again from.
  Future<int> offset({
    required Uri upload,
    required Map<String, String> auth,
  }) async {
    final response = await _http
        .head(upload, headers: {...auth, ..._version})
        .timeout(StorageRest.timeout);
    _check(response, 'Upload failed');
    final value = int.tryParse(response.headers['upload-offset'] ?? '');
    if (value == null) {
      throw StorageRefused(
        APIResponse.error('Upload failed — the server lost track of it.'),
      );
    }
    return value;
  }

  /// Gives up on [upload], so the server can drop what it has. Best effort:
  /// an upload nobody finishes is unreferenced either way.
  Future<void> cancel({
    required Uri upload,
    required Map<String, String> auth,
  }) async {
    try {
      await _http
          .delete(upload, headers: {...auth, ..._version})
          .timeout(StorageRest.timeout);
    } catch (_) {}
  }

  /// Long enough for a piece on a slow line: 30 s plus a second for every
  /// 100 KB, so 8 MB gets a little under two minutes.
  static Duration pieceTimeout(int bytes) =>
      StorageRest.timeout + Duration(milliseconds: bytes ~/ 100);

  static void _check(http.Response response, String failed) {
    final refused = StorageRest.refusal(response, failed: failed);
    if (refused != null) {
      throw StorageRefused(refused, status: response.statusCode);
    }
  }
}
