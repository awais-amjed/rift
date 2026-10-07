import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:rift_crypto/rift_crypto.dart';

import '../classes/api_response.dart';
import 'storage_rest.dart';

/// An encrypted attachment blob ready to upload, plus the per-file key/nonce
/// that must be stored (encrypted) inside the message body to decrypt it later.
typedef SealedBlob = ({Uint8List ciphertext, String keyB64, String nonceB64});

/// Where an upload landed and what opens it: the key and nonce of an
/// encrypted blob, or the digest of a plain one (the other fields empty).
typedef UploadedBlob = ({
  String path,
  String keyB64,
  String nonceB64,
  String? sha256B64,
});

/// Uploads/downloads E2E-encrypted attachment blobs (ARCHITECTURE.md §4).
///
/// The bytes are AES-256-GCM-encrypted client-side with a fresh per-file key
/// before they ever leave the device; the server only ever stores opaque
/// ciphertext. The key/nonce travel inside the (separately-encrypted) message
/// body, never as storage metadata — so a compromised server can't decrypt a
/// blob even though it holds it.
///
/// Transport for self-hosted servers is the Storage REST API, called with the
/// same raw-HTTP + bearer-token style as [ServerRepository] so it flows through
/// the cubit's token auto-refresh. Central DMs reuse [seal]/[open] for crypto
/// but move bytes over the central Supabase SDK (see CentralDmRepository).
class AttachmentRepository {
  final CryptoRepository _crypto;
  final http.Client _http;

  AttachmentRepository({CryptoRepository? crypto, http.Client? httpClient})
    : _crypto = crypto ?? CryptoRepository(),
      _http = httpClient ?? http.Client();

  /// A random object name within a scope folder, e.g. `<scope>/ab12….bin`.
  static String buildPath(String scopePrefix) =>
      StorageRest.freshPath(scopePrefix, extension: 'bin', bytes: 16);

  // ── Crypto (shared by all transports) ─────────────────────

  /// Encrypt [data] under a fresh per-file key; returns the ciphertext blob
  /// plus the base64 key/nonce to embed in the message body.
  Future<SealedBlob> seal(Uint8List data) async {
    final key = _crypto.generateFileKey();
    final enc = await _crypto.encryptBytes(data: data, key: key);
    return (
      ciphertext: enc.ciphertext,
      keyB64: CryptoRepository.toBase64(key),
      nonceB64: CryptoRepository.toBase64(enc.iv),
    );
  }

  /// The digest a file sent unencrypted carries in place of a key, base64.
  Future<String> digest(Uint8List data) async =>
      CryptoRepository.toBase64(await _crypto.digestBytes(data));

  /// A downloaded blob's bytes: decrypted with the body-embedded key/nonce,
  /// or, for a file sent unencrypted ([sha256B64] set), checked against its
  /// digest. Throws when either fails — a file the server changed is not
  /// shown.
  Future<Uint8List> open({
    required Uint8List ciphertext,
    required String keyB64,
    required String nonceB64,
    String? sha256B64,
  }) async {
    if (sha256B64 != null) {
      if (await digest(ciphertext) != sha256B64) {
        throw const FormatException('The file does not match its digest');
      }
      return ciphertext;
    }
    return _crypto.decryptBytes(
      ciphertext: ciphertext,
      key: CryptoRepository.fromBase64(keyB64),
      iv: CryptoRepository.fromBase64(nonceB64),
    );
  }

  // ── Self-hosted Storage REST transport ────────────────────

  /// Encrypt [data] and upload it to [bucket] under [scopePrefix], or upload
  /// it as it is when [plain]. On success `data` is an [UploadedBlob].
  Future<APIResponse> upload({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String bucket,
    required String scopePrefix,
    required Uint8List data,
    bool plain = false,
  }) async {
    try {
      final SealedBlob blob;
      String? sha256B64;
      if (plain) {
        sha256B64 = await digest(data);
        blob = (ciphertext: data, keyB64: '', nonceB64: '');
      } else {
        blob = await seal(data);
      }
      final path = buildPath(scopePrefix);
      final uri = StorageRest.object(baseUrl, bucket, path);
      final resp = await _http
          .post(
            uri,
            headers: {
              ...StorageRest.headers(anonKey, bearerToken),
              'Content-Type': 'application/octet-stream',
              'x-upsert': 'false',
            },
            body: blob.ciphertext,
          )
          .timeout(StorageRest.timeout);

      final refused = StorageRest.refusal(resp, failed: 'Upload failed');
      if (refused != null) return refused;
      final UploadedBlob uploaded = (
        path: path,
        keyB64: blob.keyB64,
        nonceB64: blob.nonceB64,
        sha256B64: sha256B64,
      );
      return APIResponse.success(uploaded);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Remove blobs from [bucket] — what a client does when it deletes a message
  /// that carried attachments.
  ///
  /// The client is the right place for this and the *only* practical one. It
  /// has just decrypted the message body, so it holds the storage paths, which
  /// the server cannot read at all. And the database can't help even if it
  /// could: `storage.protect_delete()` refuses a direct DELETE on
  /// `storage.objects`, so bytes are only ever freed through this API.
  ///
  /// Best-effort by design. A message row is what people see; a blob that
  /// outlives it is undecryptable waste, and the `sweep_attachments` function
  /// collects it later. So a failure here must not stop the delete.
  Future<APIResponse> deleteObjects({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String bucket,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) return APIResponse.success({'deleted': 0});
    try {
      final uri = Uri.parse('$baseUrl/storage/v1/object/$bucket');
      final resp = await _http
          .delete(
            uri,
            headers: {
              ...StorageRest.headers(anonKey, bearerToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'prefixes': paths}),
          )
          .timeout(StorageRest.timeout);

      final refused = StorageRest.refusal(resp, failed: 'Delete failed');
      if (refused != null) return refused;
      return APIResponse.success({'deleted': paths.length});
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Download a blob from [bucket] and [open] it. On success `data` is the
  /// file's `Uint8List`.
  Future<APIResponse> download({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String bucket,
    required String path,
    required String keyB64,
    required String nonceB64,
    String? sha256B64,
  }) async {
    try {
      final uri = StorageRest.authenticated(baseUrl, bucket, path);
      final resp = await _http
          .get(uri, headers: StorageRest.headers(anonKey, bearerToken))
          .timeout(StorageRest.timeout);

      final refused = StorageRest.refusal(resp, failed: 'Download failed');
      if (refused != null) return refused;
      final clear = await open(
        ciphertext: resp.bodyBytes,
        keyB64: keyB64,
        nonceB64: nonceB64,
        sha256B64: sha256B64,
      );
      return APIResponse.success(clear);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
