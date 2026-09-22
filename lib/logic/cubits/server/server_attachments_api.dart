part of 'server_cubit.dart';

/// Attachment blobs: encrypted and uploaded before the message that names
/// them, downloaded and decrypted when it is drawn, and deleted with it.
mixin _ServerAttachmentsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  AttachmentRepository get _attachments;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  String _noTarget(String? serverId);

  /// See [ServerCubit._chatTarget].
  ({Server server, String anonKey})? _chatTarget(String? serverId);

  /// Each server owns its own attachment bucket (`002_limits.sql`), named for its
  /// id. One Supabase project can host several servers, and a shared bucket
  /// could carry only one `file_size_limit` between them — and let a member of
  /// one read another's objects. A bucket each makes both exact.
  static String _bucketFor(Server server) => 'chat-${server.id}';

  /// Encrypt + upload an attachment blob to the selected server, scoped under
  /// [scopePrefix] (channel id / DM context). On success `data` is
  /// `({String path, String keyB64, String nonceB64})`.
  /// [serverId] names a server other than the open one — a forward's
  /// destination. Omitted, it is the open one, which is every other caller.
  Future<APIResponse> uploadAttachment({
    required String scopePrefix,
    required Uint8List data,
    String? serverId,
  }) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _attachments.uploadEncrypted(
        baseUrl: target.server.supabaseUrl,
        anonKey: target.anonKey,
        bearerToken: token,
        bucket: _bucketFor(target.server),
        scopePrefix: scopePrefix,
        data: data,
      ),
    );
  }

  /// Remove attachment blobs from the selected server.
  ///
  /// Called when a message carrying them is deleted: the client has just
  /// decrypted that message, so it is the only party that knows which blobs
  /// belong to it. Best-effort — see [AttachmentRepository.deleteObjects].
  Future<APIResponse> deleteAttachments(List<String> paths) {
    final server = state.selectedServer;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) {
      return Future.value(APIResponse.error('No server selected'));
    }
    return _callWithAutoRefresh(
      (token) => _attachments.deleteObjects(
        baseUrl: server.supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
        bucket: _bucketFor(server),
        paths: paths,
      ),
    );
  }

  /// Apply this server's retention settings and clear out the attachment blobs
  /// whose messages are gone. Safe for any member to call — it removes only
  /// unreferenced objects.
  Future<APIResponse> sweepAttachments() {
    final server = state.selectedServer;
    if (server == null) {
      return Future.value(APIResponse.error('No server selected'));
    }
    return _callWithAutoRefresh(
      (token) =>
          _repository.sweepAttachments(server.supabaseUrl, bearerToken: token),
    );
  }

  /// Download + decrypt an attachment blob from the selected server. On success
  /// `data` is the decrypted `Uint8List`.
  Future<APIResponse> downloadAttachment({
    required String path,
    required String keyB64,
    required String nonceB64,
    String? serverId,
  }) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _attachments.downloadDecrypted(
        baseUrl: target.server.supabaseUrl,
        anonKey: target.anonKey,
        bearerToken: token,
        bucket: _bucketFor(target.server),
        path: path,
        keyB64: keyB64,
        nonceB64: nonceB64,
      ),
    );
  }
}
