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

  BearerToken _bearerFor(Server server);

  /// See [ServerCubit._chatTarget].
  ({Server server, String anonKey})? _chatTarget(String? serverId);

  /// Each server owns its own attachment bucket (`app.sync_server_bucket`), named for its
  /// id. One Supabase project can host several servers, and a shared bucket
  /// could carry only one `file_size_limit` between them — and let a member of
  /// one read another's objects. A bucket each makes both exact.
  static String _bucketFor(Server server) => 'chat-${server.id}';

  /// Encrypt + upload an attachment blob to the selected server, scoped under
  /// [scopePrefix] (channel id / DM context), or upload it as it is when
  /// [plain]. On success `data` is an [UploadedBlob].
  /// [serverId] names a server other than the open one — a forward's
  /// destination. Omitted, it is the open one, which is every other caller.
  Future<APIResponse> uploadAttachment({
    required String scopePrefix,
    required Uint8List data,
    bool plain = false,
    String? serverId,
  }) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _attachments.upload(
        baseUrl: target.server.supabaseUrl,
        anonKey: target.anonKey,
        bearerToken: token,
        bucket: _bucketFor(target.server),
        scopePrefix: scopePrefix,
        data: data,
        plain: plain,
      ),
    );
  }

  /// Upload one staged [file] under [scopePrefix]: one held in memory in a
  /// single request, a big one a chunk at a time with [onProgress]. Sent as
  /// it is when the sender chose that for the file, or [plain] for every file
  /// (a channel whose encryption is off).
  Future<APIResponse> uploadStaged(
    PendingAttachment file, {
    required String scopePrefix,
    String? serverId,
    TransferProgress? onProgress,
    bool plain = false,
  }) => file.streams
      ? uploadAttachmentFile(
          scopePrefix: scopePrefix,
          file: file.file!,
          length: file.size,
          plain: plain || file.plain,
          serverId: serverId,
          onProgress: onProgress,
        )
      : uploadAttachment(
          scopePrefix: scopePrefix,
          data: file.bytes!,
          plain: plain || file.plain,
          serverId: serverId,
        );

  /// Seal and upload a big [file] a chunk at a time, or send it as it is when
  /// [plain] — see `AttachmentRepository.uploadStreamed`. Same answer as
  /// [uploadAttachment], with [onProgress] as it goes.
  Future<APIResponse> uploadAttachmentFile({
    required String scopePrefix,
    required XFile file,
    required int length,
    bool plain = false,
    String? serverId,
    TransferProgress? onProgress,
  }) async {
    final target = _chatTarget(serverId);
    if (target == null) return APIResponse.error(_noTarget(serverId));
    return _attachments.uploadStreamed(
      baseUrl: target.server.supabaseUrl,
      anonKey: target.anonKey,
      token: _bearerFor(target.server),
      bucket: _bucketFor(target.server),
      scopePrefix: scopePrefix,
      file: file,
      length: length,
      plain: plain,
      onProgress: onProgress,
    );
  }

  /// Fetch [attachment] into [sink] as it is opened — the road for saving a
  /// file, which never has to be in memory whole.
  Future<APIResponse> saveAttachment({
    required Attachment attachment,
    required BlobSink sink,
    String? serverId,
    TransferProgress? onProgress,
  }) async {
    final target = _chatTarget(serverId);
    if (target == null) return APIResponse.error(_noTarget(serverId));
    return _attachments.downloadTo(
      baseUrl: target.server.supabaseUrl,
      anonKey: target.anonKey,
      token: _bearerFor(target.server),
      bucket: _bucketFor(target.server),
      attachment: attachment,
      sink: sink,
      onProgress: onProgress,
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

  /// Download + open an attachment blob from the selected server. On success
  /// `data` is the file's `Uint8List`.
  Future<APIResponse> downloadAttachment({
    required String path,
    required String keyB64,
    required String nonceB64,
    String? sha256B64,
    int? chunkSize,
    String? serverId,
  }) {
    final target = _chatTarget(serverId);
    if (target == null) {
      return Future.value(APIResponse.error(_noTarget(serverId)));
    }
    return _callFor(
      target.server,
      (token) => _attachments.download(
        baseUrl: target.server.supabaseUrl,
        anonKey: target.anonKey,
        bearerToken: token,
        bucket: _bucketFor(target.server),
        path: path,
        keyB64: keyB64,
        nonceB64: nonceB64,
        sha256B64: sha256B64,
        chunkSize: chunkSize,
      ),
    );
  }
}
