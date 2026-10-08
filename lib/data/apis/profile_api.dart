import 'dart:typed_data';

import '../../logic/services/media_store.dart';
import '../classes/api_response.dart';
import '../repositories/avatar_repository.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// The caller's own profile on the selected server: display name and avatar,
/// and the members' pictures read back.
///
/// Per-server by design — each server is its own identity, so changing your
/// name here doesn't touch any other server or your central account.
///
/// Holds nothing, so a widget builds one from the session.
class ProfileApi {
  final SessionRepository _session;

  ProfileApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;
  AvatarRepository get _avatars => _session.avatars;

  /// Upload a new avatar and point the user row at it. [imageBytes] should be
  /// the already-downscaled PNG from `AvatarImage.prepare`.
  ///
  /// The old object is intentionally left behind: another member may still be
  /// rendering it from cache, and storage is cheap next to a broken picture.
  /// It is left behind, not abandoned — the server's sweep collects every
  /// avatar object no `users.avatar_path` names once it is past the grace
  /// period, and refuses an upload from anyone already holding a screenful of
  /// them. Before that sweep learned about this bucket, every picture anybody
  /// had ever set stayed on the operator's disk for good.
  Future<APIResponse> uploadAvatar(Uint8List imageBytes) async {
    final server = _session.selectedServer;
    final anonKey = server?.supabaseKey;
    final userId = server?.user?.id;
    if (server == null || anonKey == null || userId == null) {
      return APIResponse.error('No server selected');
    }

    final uploaded = await _session.callFor(
      server,
      (token) => _avatars.upload(
        baseUrl: server.supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
        userId: userId,
        data: imageBytes,
      ),
    );
    if (!uploaded.success) return uploaded;

    final path = uploaded.data as String;
    // In the store before the row moves, so the re-read that lands the new
    // path finds the picture already there instead of fetching it back.
    MediaStore.images.put(path, imageBytes);
    final saved = await updateProfile(avatarPath: path, clearAvatar: false);
    if (!saved.success) return saved;
    return APIResponse.success(path);
  }

  /// Fetch one member's avatar bytes, through [MediaStore.images] so every
  /// widget showing it sees the result. Null when the fetch fails.
  Future<Uint8List?> loadAvatar(String path) =>
      MediaStore.images.load(path, () => _downloadAvatar(path));

  Future<Uint8List?> _downloadAvatar(String path) async {
    final server = _session.selectedServer;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _avatars.download(
        baseUrl: server.supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
        path: path,
      ),
    );
    if (!response.success) return null;
    return response.data as Uint8List;
  }

  /// Update the caller's display name and/or avatar. Pass [clearAvatar] to
  /// remove the picture — distinct from "leave it alone", which is what a null
  /// [avatarPath] means.
  ///
  /// Ends with a re-read of the server's details, which the list lands before
  /// this answers: the name and picture appear all over the UI, and nothing
  /// should draw the old ones once the dialog has said it saved.
  Future<APIResponse> updateProfile({
    String? displayName,
    String? avatarPath,
    bool clearAvatar = false,
  }) async {
    final server = _session.selectedServer;
    final userId = server?.user?.id;
    if (server == null || userId == null) {
      return APIResponse.error('No server selected');
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.updateProfile(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        userId: userId,
        bearerToken: token,
        displayName: displayName,
        avatarPath: avatarPath,
        clearAvatar: clearAvatar,
      ),
    );
    if (!response.success) return response;

    await _session.refreshDetails(server);
    return response;
  }
}
