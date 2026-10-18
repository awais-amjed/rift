import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import '../classes/api_response.dart';
import '../classes/attachment.dart';
import '../classes/pending_attachment.dart';
import '../classes/server.dart';
import '../repositories/attachment_repository.dart';
import '../repositories/blob/blob_sink.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// Attachment blobs on a server: encrypted and uploaded before the message
/// that names them, downloaded and decrypted when it is drawn, and deleted
/// with it.
///
/// Bound to one server, like every class here. A forward fetches with one
/// server's and uploads with another's.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class AttachmentsApi {
  final ServerSession _target;

  AttachmentsApi(this._target);

  SessionRepository get _session => _target.session;

  AttachmentRepository get _attachments => _session.attachments;

  /// Each server owns its own attachment bucket (`app.sync_server_bucket`),
  /// named for its id. One Supabase project can host several servers, and a
  /// shared bucket could carry only one `file_size_limit` between them — and
  /// let a member of one read another's objects. A bucket each makes both
  /// exact.
  static String _bucketFor(Server server) => 'chat-${server.id}';

  /// The server with its key — or null when it is gone, or has no key yet.
  ///
  /// Resolved once for both halves of a call: a blob sealed for one server and
  /// uploaded to another is a link nobody in either can open.
  ({Server server, String anonKey})? _withKey() {
    final server = _target.server;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) return null;
    return (server: server, anonKey: anonKey);
  }

  /// Upload one staged [file] under [scopePrefix]: one held in memory in a
  /// single request, a big one a chunk at a time with [onProgress]. Sent as
  /// it is when the sender chose that for the file and [mayGoPlain] lets it,
  /// or [plain] for every file (a channel whose encryption is off). On
  /// success `data` is an [UploadedBlob].
  ///
  /// [mayGoPlain] is a public channel's: a server from before
  /// `chat_attachments_select` asked about the channel lets any of its
  /// members fetch any stored file, so a plain file anywhere else would be
  /// open to the whole server. Off by default, so a path that forgets it
  /// seals the file.
  Future<APIResponse> uploadStaged(
    PendingAttachment file, {
    required String scopePrefix,
    TransferProgress? onProgress,
    bool plain = false,
    bool mayGoPlain = false,
  }) {
    final asItIs = plain || (mayGoPlain && file.plain);
    return file.streams
        ? _uploadFile(
            scopePrefix: scopePrefix,
            file: file.file!,
            length: file.size,
            plain: asItIs,
            onProgress: onProgress,
          )
        : _upload(scopePrefix: scopePrefix, data: file.bytes!, plain: asItIs);
  }

  /// Encrypt + upload a blob held in memory, or upload it as it is when
  /// [plain].
  Future<APIResponse> _upload({
    required String scopePrefix,
    required Uint8List data,
    required bool plain,
  }) async {
    final target = _withKey();
    if (target == null) return APIResponse.error(ServerSession.gone);
    return _session.callFor(
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

  /// Seal and upload a big [file] a chunk at a time, or send it as it is when
  /// [plain] — see `AttachmentRepository.uploadStreamed`. Same answer as
  /// [_upload], with [onProgress] as it goes.
  Future<APIResponse> _uploadFile({
    required String scopePrefix,
    required XFile file,
    required int length,
    required bool plain,
    TransferProgress? onProgress,
  }) async {
    final target = _withKey();
    if (target == null) return APIResponse.error(ServerSession.gone);
    return _attachments.uploadStreamed(
      baseUrl: target.server.supabaseUrl,
      anonKey: target.anonKey,
      token: _session.bearerFor(target.server),
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
    TransferProgress? onProgress,
  }) async {
    final target = _withKey();
    if (target == null) return APIResponse.error(ServerSession.gone);
    return _attachments.downloadTo(
      baseUrl: target.server.supabaseUrl,
      anonKey: target.anonKey,
      token: _session.bearerFor(target.server),
      bucket: _bucketFor(target.server),
      attachment: attachment,
      sink: sink,
      onProgress: onProgress,
    );
  }

  /// Download + open an attachment blob. On success `data` is the file's
  /// `Uint8List`.
  Future<APIResponse> downloadAttachment({
    required String path,
    required String keyB64,
    required String nonceB64,
    String? sha256B64,
    int? chunkSize,
  }) async {
    final target = _withKey();
    if (target == null) return APIResponse.error(ServerSession.gone);
    return _session.callFor(
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

  /// Remove attachment blobs.
  ///
  /// Called when a message carrying them is deleted: the client has just
  /// decrypted that message, so it is the only party that knows which blobs
  /// belong to it. Best-effort — see [AttachmentRepository.deleteObjects].
  Future<APIResponse> deleteAttachments(List<String> paths) async {
    final target = _withKey();
    if (target == null) return APIResponse.error(ServerSession.gone);
    return _session.callFor(
      target.server,
      (token) => _attachments.deleteObjects(
        baseUrl: target.server.supabaseUrl,
        anonKey: target.anonKey,
        bearerToken: token,
        bucket: _bucketFor(target.server),
        paths: paths,
      ),
    );
  }

  /// Apply the server's retention settings and clear out the
  /// attachment blobs whose messages are gone. Safe for any member to call —
  /// it removes only unreferenced objects.
  Future<APIResponse> sweepAttachments() async {
    final server = _target.server;
    if (server == null) return APIResponse.error(ServerSession.gone);
    return _session.callFor(
      server,
      (token) => _session.repository.sweepAttachments(
        server.supabaseUrl,
        bearerToken: token,
      ),
    );
  }
}
