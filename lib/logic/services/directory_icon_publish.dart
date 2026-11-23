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
/// Answers the stored path, or none with [failed] saying why: nothing to copy
/// (no icon, so the listing draws its initial) or a copy that failed, which is
/// not worth failing a publish over but must not take a picture the listing
/// already has off it either — the caller keeps that one.
class DirectoryIconPublish {
  const DirectoryIconPublish._();

  /// Refused as it arrives rather than after. A server icon is capped at 2 MB
  /// by its own bucket, and this only has to survive a source that is not one.
  static const int _maxSourceBytes = 8 * 1024 * 1024;

  static final DirectoryIconRepository _icons = DirectoryIconRepository();

  /// Fetch [sourceUrl], downscale it, and store it on central.
  ///
  /// Only `https` and `http`: the address comes from the server row, which an
  /// admin of that server writes, and there is no reason for this to be
  /// handing anything else to an HTTP client. See `open_link.dart` for the
  /// same rule in front of the other place a URL arrives from elsewhere.
  static Future<({String? path, bool failed})> copyToCentral(
    String? sourceUrl,
  ) async {
    const none = (path: null, failed: false);
    const failed = (path: null, failed: true);
    if (sourceUrl == null || sourceUrl.isEmpty) return none;
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) return none;
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'https' && scheme != 'http') || uri.host.isEmpty) {
      return none;
    }

    final source = await _icons.fetchSource(uri, maxBytes: _maxSourceBytes);
    if (source == null) return failed;

    // The same downscale an avatar gets, so the bucket's 256 KB ceiling is
    // met by what we send rather than discovered by what it refuses.
    final prepared = await AvatarImage.prepare(source);
    if (prepared == null) return failed;

    final stored = await _icons.upload(prepared);
    return stored.success
        ? (path: stored.data as String, failed: false)
        : failed;
  }
}
