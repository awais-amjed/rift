import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../classes/api_response.dart';

/// The picture beside a listing in the directory, stored on central.
///
/// Listings used to carry an `icon_url` and the browser drew it straight from
/// that address — which the *publisher* chose. Opening the directory therefore
/// fetched a picture from every listed party at once, so each of them learned
/// the address and the minute of everyone who was only looking, including the
/// listings nobody went on to join. For a server that URL was its own public
/// icon bucket, which needs no session, so the operator saw raw addresses.
///
/// It is the same tracking [LinkPreview] exists to refuse, answered the same
/// way: the bytes are captured once, by the person who chose them, and served
/// from central afterwards. Central learns who browsed, and already did — it
/// served the rows.
///
/// The bucket is private, so reading needs the caller's own session; the
/// directory already does, since both listing tables are `TO authenticated`.
class DirectoryIconRepository {
  static const String bucket = 'directory-icons';

  SupabaseClient get _client => Supabase.instance.client;

  /// `<uid>/<sha-256 of the bytes>`, which is two rules at once.
  ///
  /// The `<uid>` half matches the bucket's own-folder write policy — a path
  /// under anybody else's id is refused there, not here.
  ///
  /// The digest half makes an upload idempotent, and that is what keeps the
  /// per-account ceiling honest. Editing a listing republishes it, and a
  /// random segment would mint a fresh object on every Save — twelve saves and
  /// an account is at its limit with twelve copies of one picture. The same
  /// bytes now name the same object, so re-saving an unchanged icon uploads
  /// nothing and a changed one costs exactly one.
  Future<String?> _pathFor(Uint8List data) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final digest = await Sha256().hash(data);
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$uid/$hex.img';
  }

  /// Upload [data] — already downscaled by `AvatarImage.prepare` — and answer
  /// the object path to store on the listing.
  ///
  /// An object that is already there is the success case, not a collision: the
  /// path is the digest of these exact bytes, so whatever is sitting at it is
  /// this picture. The bucket has no UPDATE policy by design, so there is
  /// nothing to overwrite and nothing that needs to be.
  Future<APIResponse> upload(Uint8List data) async {
    final path = await _pathFor(data);
    if (path == null) return APIResponse.error('Not signed in');
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            data,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
      return APIResponse.success(path);
    } on StorageException catch (e) {
      if (e.statusCode == '409' || e.error == 'Duplicate') {
        return APIResponse.success(path);
      }
      return APIResponse.error(e.message);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Fetch one listing's icon bytes. Null rather than an error: a directory
  /// row whose picture will not load draws its initial, which is what a
  /// listing with no icon at all already does.
  Future<Uint8List?> download(String path) async {
    try {
      return await _client.storage.from(bucket).download(path);
    } catch (_) {
      return null;
    }
  }
}
