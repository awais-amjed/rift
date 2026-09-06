import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../classes/api_response.dart';

/// Uploads/downloads avatar images for a self-hosted server.
///
/// Unlike [AttachmentRepository] these bytes are **not encrypted** — an avatar
/// is shown to every member, so per-member wrapping of a picture everyone sees
/// anyway buys nothing (`005_bots.sql`). The bucket is still private: reading
/// requires a member token, so avatars aren't exposed to the unauthenticated
/// internet.
///
/// Same raw-HTTP + bearer-token style as the other repositories, so calls flow
/// through the cubit's token auto-refresh.
class AvatarRepository {
  static const String bucket = 'avatars';

  final http.Client _http;

  AvatarRepository({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static final _rng = Random.secure();

  /// `<userId>/<random>.img`. The random segment means a new upload never
  /// collides with the cached copy of the old one — clients key their cache on
  /// the path, so reusing it would show a stale picture.
  static String buildPath(String userId) {
    final id = List.generate(
      12,
      (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$userId/$id.img';
  }

  Map<String, String> _headers(String anonKey, String bearerToken) => {
    'apikey': anonKey,
    'Authorization': 'Bearer $bearerToken',
  };

  /// Upload [data] (already downscaled + re-encoded as PNG). On success `data`
  /// is the object path to store on the user row.
  Future<APIResponse> upload({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String userId,
    required Uint8List data,
  }) async {
    try {
      final path = buildPath(userId);
      final resp = await _http
          .post(
            Uri.parse('$baseUrl/storage/v1/object/$bucket/$path'),
            headers: {
              ..._headers(anonKey, bearerToken),
              'Content-Type': 'image/png',
              'x-upsert': 'false',
            },
            body: data,
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return APIResponse.error('Not authorized', errorCode: 'token_expired');
      }
      if (resp.statusCode >= 300) {
        return APIResponse.error('Avatar upload failed (${resp.statusCode})');
      }
      return APIResponse.success(path);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Fetch one avatar's bytes. On success `data` is a `Uint8List`.
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
        return APIResponse.error('Avatar download failed (${resp.statusCode})');
      }
      return APIResponse.success(resp.bodyBytes);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
