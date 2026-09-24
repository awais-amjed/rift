import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../data/repositories/directory_icon_repository.dart';
import 'avatar_image.dart';

/// Copies a server's own icon into central, for the listing to point at.
///
/// A server's picture lives in that server's `servers` bucket, which is
/// **public** — it has to be, because the join screen draws it before anybody
/// has a session. Pointing the directory straight at that address is what let
/// every listed operator log the address of everyone merely browsing, so the
/// bytes are taken once here, by the admin publishing the listing, and served
/// from central afterwards.
///
/// Returns null when there is nothing to copy or the copy fails, which is not
/// an error worth failing a publish over: the listing simply draws its initial,
/// exactly as one that never had a picture does.
class DirectoryIconPublish {
  const DirectoryIconPublish._();

  /// Refused before the download finishes rather than after. A server icon is
  /// capped at 5 MB by its own bucket, and this only has to survive a source
  /// that is not one.
  static const int _maxSourceBytes = 8 * 1024 * 1024;

  static final DirectoryIconRepository _icons = DirectoryIconRepository();

  /// Fetch [sourceUrl], downscale it, and store it on central.
  ///
  /// Only `https` and `http`: the address comes from the server row, which an
  /// admin of that server writes, and there is no reason for this to be
  /// handing anything else to an HTTP client. See `open_link.dart` for the
  /// same rule in front of the other place a URL arrives from elsewhere.
  static Future<String?> copyToCentral(String? sourceUrl) async {
    if (sourceUrl == null || sourceUrl.isEmpty) return null;
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'https' && scheme != 'http') || uri.host.isEmpty) return null;

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final source = Uint8List.fromList(response.bodyBytes);
      if (source.length > _maxSourceBytes) return null;

      // The same downscale an avatar gets, so the bucket's 256 KB ceiling is
      // met by what we send rather than discovered by what it refuses.
      final prepared = await AvatarImage.prepare(source);
      if (prepared == null) return null;

      final stored = await _icons.upload(prepared);
      return stored.success ? stored.data as String : null;
    } catch (_) {
      return null;
    }
  }
}
