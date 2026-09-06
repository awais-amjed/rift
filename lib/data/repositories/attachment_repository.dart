import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:rift_crypto/rift_crypto.dart';

import '../classes/api_response.dart';

/// An encrypted attachment blob ready to upload, plus the per-file key/nonce
/// that must be stored (encrypted) inside the message body to decrypt it later.
typedef SealedBlob = ({Uint8List ciphertext, String keyB64, String nonceB64});

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

  static final _rng = Random.secure();

  /// A random object name within a scope folder, e.g. `<scope>/ab12….bin`.
  static String buildPath(String scopePrefix) {
    final id = List.generate(
      16,
      (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$scopePrefix/$id.bin';
  }

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

  /// Decrypt a downloaded ciphertext blob with the body-embedded key/nonce.
  Future<Uint8List> open({
    required Uint8List ciphertext,
    required String keyB64,
    required String nonceB64,
  }) => _crypto.decryptBytes(
    ciphertext: ciphertext,
    key: CryptoRepository.fromBase64(keyB64),
    iv: CryptoRepository.fromBase64(nonceB64),
  );

  // ── Self-hosted Storage REST transport ────────────────────

  Map<String, String> _headers(String anonKey, String bearerToken) => {
    'apikey': anonKey,
    'Authorization': 'Bearer $bearerToken',
  };

  /// Encrypt [data] and upload it to [bucket] under [scopePrefix].
  /// On success `data` is `({String path, String keyB64, String nonceB64})`.
  Future<APIResponse> uploadEncrypted({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String bucket,
    required String scopePrefix,
    required Uint8List data,
  }) async {
    try {
      final blob = await seal(data);
      final path = buildPath(scopePrefix);
      final uri = Uri.parse('$baseUrl/storage/v1/object/$bucket/$path');
      final resp = await _http
          .post(
            uri,
            headers: {
              ..._headers(anonKey, bearerToken),
              'Content-Type': 'application/octet-stream',
              'x-upsert': 'false',
            },
            body: blob.ciphertext,
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return APIResponse.error('Not authorized', errorCode: 'token_expired');
      }
      if (resp.statusCode >= 300) {
        return APIResponse.error('Upload failed (${resp.statusCode})');
      }
      return APIResponse.success((
        path: path,
        keyB64: blob.keyB64,
        nonceB64: blob.nonceB64,
      ));
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
              ..._headers(anonKey, bearerToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'prefixes': paths}),
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return APIResponse.error('Not authorized', errorCode: 'token_expired');
      }
      if (resp.statusCode >= 300) {
        return APIResponse.error('Delete failed (${resp.statusCode})');
      }
      return APIResponse.success({'deleted': paths.length});
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Download and decrypt a blob from [bucket]. On success `data` is the
  /// decrypted `Uint8List`.
  Future<APIResponse> downloadDecrypted({
    required String baseUrl,
    required String anonKey,
    required String bearerToken,
    required String bucket,
    required String path,
    required String keyB64,
    required String nonceB64,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/storage/v1/object/authenticated/$bucket/$path',
      );
      final resp = await _http
          .get(uri, headers: _headers(anonKey, bearerToken))
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return APIResponse.error('Not authorized', errorCode: 'token_expired');
      }
      if (resp.statusCode >= 300) {
        return APIResponse.error('Download failed (${resp.statusCode})');
      }
      final clear = await open(
        ciphertext: resp.bodyBytes,
        keyB64: keyB64,
        nonceB64: nonceB64,
      );
      return APIResponse.success(clear);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
