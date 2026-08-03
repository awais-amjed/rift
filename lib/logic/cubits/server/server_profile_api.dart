part of 'server_cubit.dart';

/// The caller's own profile on the selected server: display name and avatar.
///
/// Per-server by design — each server is its own identity, so changing your
/// name here doesn't touch any other server or your central account.
mixin _ServerProfileApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  AvatarRepository get _avatars;
  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Upload a new avatar and point the user row at it. [imageBytes] should be
  /// the already-downscaled PNG from `AvatarImage.prepare`.
  ///
  /// The old object is intentionally left behind: another member may still be
  /// rendering it from cache, and storage is cheap next to a broken picture.
  Future<APIResponse> uploadAvatar(Uint8List imageBytes) async {
    final server = state.selectedServer;
    final anonKey = server?.supabaseKey;
    final userId = server?.user?.id;
    if (server == null || anonKey == null || userId == null) {
      return APIResponse.error('No server selected');
    }

    final uploaded = await _callWithAutoRefresh(
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
    final saved = await updateProfile(avatarPath: path, clearAvatar: false);
    if (!saved.success) return saved;
    // Serve our own new picture from cache immediately.
    AvatarCache.instance.put(path, imageBytes);
    return APIResponse.success(path);
  }

  /// Fetch one member's avatar bytes, cache-first. Null when they have none or
  /// the fetch fails — callers fall back to initials.
  Future<Uint8List?> loadAvatar(String path) async {
    final cached = AvatarCache.instance.get(path);
    if (cached != null) return cached;

    final server = state.selectedServer;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) return null;

    final response = await _callWithAutoRefresh(
      (token) => _avatars.download(
        baseUrl: server.supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
        path: path,
      ),
    );
    if (!response.success) return null;
    final bytes = response.data as Uint8List;
    AvatarCache.instance.put(path, bytes);
    return bytes;
  }

  /// Update the caller's display name and/or avatar. Pass [clearAvatar] to
  /// remove the picture — distinct from "leave it alone", which is what a null
  /// [avatarPath] means.
  Future<APIResponse> updateProfile({
    String? displayName,
    String? avatarPath,
    bool clearAvatar = false,
  }) async {
    final server = state.selectedServer;
    if (server == null) return APIResponse.error('No server selected');

    final response = await _callWithAutoRefresh(
      (token) => _repository.updateProfile(
        server.supabaseUrl,
        bearerToken: token,
        displayName: displayName,
        avatarPath: avatarPath,
        clearAvatar: clearAvatar,
      ),
    );
    if (!response.success) return response;

    // Reflect it locally without a refetch: the name and picture appear all
    // over the UI and a round-trip would leave them stale in the meantime.
    final data = response.data as Map<String, dynamic>;
    final user = server.user;
    if (user != null) {
      final updated = server.copyWith(
        user: ServerUser(
          id: user.id,
          username: user.username,
          displayName: data['display_name'] as String? ?? user.displayName,
          permissions: user.permissions,
          avatarPath: data['avatar_path'] as String?,
        ),
      );
      _replaceServer(updated);
    }
    return response;
  }

  /// Implemented by the cubit — swaps one server in the list + selection.
  void _replaceServer(Server server);
}
