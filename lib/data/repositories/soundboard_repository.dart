import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../logic/services/byte_format.dart';
import '../classes/api_response.dart';
import 'storage_rest.dart';

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
  ///
  /// It is [SoundboardPlay.maxPlayback] written as bytes: half a minute of
  /// WAV at 44.1 kHz/16-bit stereo is about 5.3 MB, and `wav` is one of the
  /// formats every target can decode. Anything compressed is far under it,
  /// so this only ever catches a file that was not going to be a clip.
  static const int maxBytes = 5 * 1024 * 1024;

  final http.Client _http;

  SoundboardRepository({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// `<serverId>/<random>.audio`. The server id is the read policy's whole
  /// rule, and the random segment means a path is never reused — which is
  /// what lets every client cache a clip's bytes forever under its path.
  static String buildPath(String serverId) =>
      StorageRest.freshPath(serverId, extension: 'audio');

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
            StorageRest.object(baseUrl, bucket, path),
            headers: {
              ...StorageRest.headers(anonKey, bearerToken),
              'Content-Type': contentType,
              'x-upsert': 'false',
            },
            body: data,
          )
          .timeout(StorageRest.timeout);

      if (resp.statusCode == 413) {
        return APIResponse.error(
          'That clip is too big — ${humanSize(maxBytes)} at most',
        );
      }

      final refused = StorageRest.refusal(resp, failed: 'Upload failed');
      if (refused != null) return refused;
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
            StorageRest.authenticated(baseUrl, bucket, path),
            headers: StorageRest.headers(anonKey, bearerToken),
          )
          .timeout(StorageRest.timeout);

      final refused = StorageRest.refusal(resp, failed: 'Download failed');
      if (refused != null) return refused;
      return APIResponse.success(resp.bodyBytes);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Remove one clip's bytes.
  ///
  /// Through the Storage API and not a `DELETE FROM storage.objects`, which
  /// used to be a trigger on the row: Storage guards that table against
  /// direct deletion, and even with the guard opted out it would have
  /// removed the row while leaving the file itself on the host's disk
  /// forever. Only this endpoint knows where the bytes are.
  ///
  /// Called *after* the row is gone, so a failure here leaks an object
  /// rather than leaving a clip in every picker with nothing behind it.
  Future<APIResponse> deleteObject({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String path,
  }) async {
    try {
      final resp = await _http
          .delete(
            StorageRest.object(baseUrl, bucket, path),
            headers: StorageRest.headers(anonKey, bearerToken),
          )
          .timeout(const Duration(seconds: 15));

      // A clip whose file is already gone is the state we wanted.
      if (resp.statusCode == 404) return APIResponse.success(null);

      final refused = StorageRest.refusal(resp, failed: 'Delete failed');
      if (refused != null) return refused;
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
