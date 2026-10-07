import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../logic/helper_methods.dart';
import '../classes/api_response.dart';

/// What every repository that keeps files on a self-hosted server's Storage
/// shares: the headers, the object URLs, fresh object names, and reading a
/// reply that did not succeed.
///
/// Attachments, avatars and soundboard clips each used to carry their own
/// copy. The copies agreed, but the one line that matters is easy to drop: a
/// 401 or 403 has to come back as `token_expired`, because that code is what
/// `ServerCubit._callWithAutoRefresh` re-authenticates on. A copy that forgot
/// it would turn an expired session into a failed upload.
abstract final class StorageRest {
  static final _rng = Random.secure();

  /// How long an upload or download may take before it is given up on.
  static const Duration timeout = Duration(seconds: 30);

  static Map<String, String> headers(String anonKey, String bearerToken) => {
    'apikey': anonKey,
    'Authorization': 'Bearer $bearerToken',
  };

  /// Where [path] is written to and deleted from.
  static Uri object(String baseUrl, String bucket, String path) =>
      Uri.parse('$baseUrl/storage/v1/object/$bucket/$path');

  /// Where [path] is read from, with the caller's token — every bucket here is
  /// private.
  static Uri authenticated(String baseUrl, String bucket, String path) =>
      Uri.parse('$baseUrl/storage/v1/object/authenticated/$bucket/$path');

  /// A new object name under [folder]: [bytes] random bytes in hex, then
  /// [extension].
  ///
  /// Never reused. Clients cache a file's bytes under its path for good, so
  /// writing new bytes to an old path would leave everybody showing the old
  /// ones.
  static String freshPath(
    String folder, {
    required String extension,
    int bytes = 12,
  }) {
    final id = List.generate(
      bytes,
      (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$folder/$id.$extension';
  }

  /// [body] sent to [uri] as it is. `client.post(body: bytes)` does not:
  /// it wraps the bytes in a cast view and copies them back one at a time,
  /// on the UI isolate. Measured Oct 7 on a phone, that was 110 ms for each
  /// 16 MB piece of a big upload, the window frozen every time.
  static Future<http.Response> sendBytes(
    http.Client client,
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required Uint8List body,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = body;
    return http.Response.fromStream(await client.send(request));
  }

  /// What [response] means when it is not a success, or null when it is.
  ///
  /// [failed] names the operation: "Upload failed", "Avatar upload failed".
  ///
  /// The status code goes to the log rather than into the sentence. It used
  /// to be the sentence — "Upload failed (500)" — which tells somebody whose
  /// picture would not send nothing they can act on, and tells whoever is
  /// debugging it no more than the log already does.
  static APIResponse? refusal(
    http.Response response, {
    required String failed,
  }) {
    final code = response.statusCode;
    if (code == 401 || code == 403) {
      return APIResponse.error('Not authorized', errorCode: 'token_expired');
    }
    if (code < 300) return null;
    HelperMethods.printDebug('[Storage] $failed: HTTP $code');
    if (code == 413) {
      return APIResponse.error(
        '$failed — the file is bigger than this server takes.',
      );
    }
    return APIResponse.error(
      code >= 500
          ? '$failed — the server is having trouble. Try again in a moment.'
          : '$failed — the server would not accept it.',
    );
  }
}
