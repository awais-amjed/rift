import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../classes/api_response.dart';
import 'storage_rest.dart';

/// Uploads/downloads avatar images for a self-hosted server.
///
/// Unlike [AttachmentRepository] these bytes are **not encrypted** — an avatar
/// is shown to every member, so per-member wrapping of a picture everyone sees
/// anyway buys nothing. The bucket is still private: reading
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

  /// `<userId>/<random>.img`. The random segment means a new upload never
  /// collides with the cached copy of the old one — clients key their cache on
  /// the path, so reusing it would show a stale picture.
  static String buildPath(String userId) =>
      StorageRest.freshPath(userId, extension: 'img');

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
      final resp = await StorageRest.sendBytes(
        _http,
        'POST',
        StorageRest.object(baseUrl, bucket, path),
        headers: {
          ...StorageRest.headers(anonKey, bearerToken),
          'Content-Type': 'image/png',
          'x-upsert': 'false',
        },
        body: data,
      ).timeout(StorageRest.timeout);

      final refused = StorageRest.refusal(resp, failed: 'Avatar upload failed');
      if (refused != null) return refused;
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
            StorageRest.authenticated(baseUrl, bucket, path),
            headers: StorageRest.headers(anonKey, bearerToken),
          )
          .timeout(StorageRest.timeout);

      final refused = StorageRest.refusal(
        resp,
        failed: 'Avatar download failed',
      );
      if (refused != null) return refused;
      return APIResponse.success(resp.bodyBytes);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
