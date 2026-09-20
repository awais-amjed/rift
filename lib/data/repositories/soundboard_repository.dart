import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../classes/api_response.dart';

/// Uploads and downloads soundboard clips for a self-hosted server.
///
/// Like [AvatarRepository] and unlike [AttachmentRepository], these bytes are
/// **not encrypted**: a clip every member plays gains nothing from per-member
/// wrapping, which is the trade-off avatars and reactions already make. The
/// bucket is private, so it still takes a member token to read one.
///
/// One bucket for the whole project, with a folder per server — the read
/// policy names the folder. Attachments get a bucket each instead, because
/// there the *size cap* differs per server and a bucket is where that number
/// lives; here it is the same number for everybody.
class SoundboardRepository {
  static const String bucket = 'soundboard';

  /// The server-side ceiling, mirrored here only so a file can be refused
  /// before it is uploaded rather than after (`006_storage.sql`).
  static const int maxBytes = 512 * 1024;

  final http.Client _http;

  SoundboardRepository({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static final _rng = Random.secure();

  /// `<serverId>/<random>.audio`. The server id is the read policy's whole
  /// rule, and the random segment means a path is never reused — which is
  /// what lets every client cache a clip's bytes forever under its path.
  static String buildPath(String serverId) {
    final id = List.generate(
      12,
      (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$serverId/$id.audio';
  }

  Map<String, String> _headers(String anonKey, String bearerToken) => {
    'apikey': anonKey,
    'Authorization': 'Bearer $bearerToken',
  };

  /// Upload [data]. On success `data` is the object path to store on the row.
  ///
  /// [contentType] is what the file said it was. Nothing decodes it here, and
  /// nothing on the server does either — what plays it is the listener's
  /// audio stack, which will refuse a file it cannot read.
  Future<APIResponse> upload({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String serverId,
    required Uint8List data,
    required String contentType,
  }) async {
    try {
      final path = buildPath(serverId);
      final resp = await _http
          .post(
            Uri.parse('$baseUrl/storage/v1/object/$bucket/$path'),
            headers: {
              ..._headers(anonKey, bearerToken),
              'Content-Type': contentType,
              'x-upsert': 'false',
            },
            body: data,
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return APIResponse.error('Not authorized', errorCode: 'token_expired');
      }
      if (resp.statusCode == 413) {
        return APIResponse.error('That clip is too big — 512 KB at most');
      }
      if (resp.statusCode >= 300) {
        return APIResponse.error('Upload failed (${resp.statusCode})');
      }
      return APIResponse.success(path);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Fetch one clip's bytes. On success `data` is a `Uint8List`.
  Future<APIResponse> download({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String path,
  }) async {
    try {
      final resp = await _http
          .get(
            Uri.parse('$baseUrl/storage/v1/object/authenticated/$bucket/$path'),
            headers: _headers(anonKey, bearerToken),
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return APIResponse.error('Not authorized', errorCode: 'token_expired');
      }
      if (resp.statusCode >= 300) {
        return APIResponse.error('Download failed (${resp.statusCode})');
      }
      return APIResponse.success(resp.bodyBytes);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
