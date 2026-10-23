import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../classes/api_response.dart';
import 'storage_rest.dart';

/// A server's own icon, in its folder of the project's `servers` bucket.
///
/// The bucket is **public**, unlike `avatars`: the screen that opens an invite
/// draws the icon before the person opening it has a session. So reading
/// needs no token, and nothing here reads with one.
///
/// What the app draws is always a path read from this server's own Storage,
/// never an address from the row. `servers.icon_url` is written by an admin,
/// and when it held an address every member's app fetched from whatever host
/// it named. `update_server` now refuses anything but a path in the server's
/// own folder, and [isIconOf] refuses the rest here too, for a server that is
/// older than that rule.
class ServerIconRepository {
  static const String bucket = 'servers';

  final http.Client _http;

  ServerIconRepository({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// Whether [path] is one of [serverId]'s icons: in its folder, and named the
  /// way [upload] names them.
  static bool isIconOf(String serverId, String? path) {
    if (path == null || !path.startsWith('$serverId/')) return false;
    return RegExp(
      r'^[0-9a-f]{8,64}\.img$',
    ).hasMatch(path.substring(serverId.length + 1));
  }

  /// Where anybody reads [path] from, signed in or not.
  static Uri publicUrl(String baseUrl, String path) =>
      Uri.parse('$baseUrl/storage/v1/object/public/$bucket/$path');

  /// [publicUrl] for [serverId]'s icon at [path], or null when [path] is not
  /// one of its icons.
  static String? publicUrlOf(String baseUrl, String serverId, String? path) =>
      isIconOf(serverId, path) ? publicUrl(baseUrl, path!).toString() : null;

  /// Upload [data] (already downscaled and re-encoded as PNG by
  /// `AvatarImage.prepare`). On success `data` is the object path, for
  /// `update_server` to store.
  ///
  /// A fresh random path every time, as for avatars: clients keep a picture
  /// under its path, so new bytes under an old one would never be drawn.
  Future<APIResponse> upload({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String serverId,
    required Uint8List data,
  }) async {
    try {
      final path = StorageRest.freshPath(serverId, extension: 'img');
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

      final refused = StorageRest.refusal(resp, failed: 'Icon upload failed');
      if (refused != null) return refused;
      return APIResponse.success(path);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Fetch one icon's bytes, or null when the fetch fails.
  Future<Uint8List?> download({
    required String baseUrl,
    required String path,
  }) async {
    try {
      final resp = await _http
          .get(publicUrl(baseUrl, path))
          .timeout(StorageRest.timeout);
      if (resp.statusCode != 200) return null;
      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
