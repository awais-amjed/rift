import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../classes/chat_identity.dart';
import '../classes/message_envelope.dart';
import '../classes/server_identity.dart';
import '../classes/wrapped_key.dart';

export '../classes/chat_identity.dart';
export '../classes/message_envelope.dart';
export '../classes/server_identity.dart';
export '../classes/wrapped_key.dart';

part 'crypto_repository_chat.dart';

/// Repository wrapping all cryptographic operations.
///
/// Uses the `cryptography` package for Argon2id, AES-GCM, HMAC-SHA256,
/// Ed25519, X25519, and secure random generation. Chat/messaging crypto
/// lives in the `_ChatCryptoMixin` part.
class CryptoRepository with _ChatCryptoMixin {
  // ──────────────────────────────────────────────────────────
  // Random generation
  // ──────────────────────────────────────────────────────────

  /// Generate a cryptographically secure 256-bit (32 byte) master seed.
  Uint8List generateMasterSeed() => _secureRandomBytes(32);

  /// Generate a cryptographically secure 256-bit (32 byte) salt.
  Uint8List generateSalt() => _secureRandomBytes(32);

  static Uint8List _secureRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Argon2id — Vault key derivation
  // ──────────────────────────────────────────────────────────

  /// Derive a 256-bit Vault Key from [password] + [salt] using Argon2id.
  ///
  /// Runs in a background isolate to avoid blocking the UI.
  Future<Uint8List> deriveVaultKey({
    required String password,
    required Uint8List salt,
    int memoryKiB = 65536,
    int iterations = 2,
    int parallelism = 1,
  }) async {
    return Isolate.run(() async {
      final algorithm = Argon2id(
        memory: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: 32,
      );

      final secretKey = await algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      final keyBytes = await secretKey.extractBytes();
      return Uint8List.fromList(keyBytes);
    });
  }

  // ──────────────────────────────────────────────────────────
  // Split-key account derivation (Option B — see ARCHITECTURE.md §3)
  // ──────────────────────────────────────────────────────────

  /// Derives two independent keys from one account password so the real
  /// password never leaves the device:
  ///
  /// ```
  /// stretched     = Argon2id(password, salt: SHA-256(normalized email))
  /// authPassword  = base64( HMAC-SHA256(stretched, "account:auth:v1") )
  /// vaultPassword = base64( HMAC-SHA256(stretched, "account:vault:v1") )
  /// ```
  ///
  /// [authPassword] is sent to the central Supabase as the login password
  /// (GoTrue bcrypts it again server-side). [vaultPassword] feeds the existing
  /// Argon2id seed encryption via [deriveVaultKey] and must never be persisted
  /// or transmitted.
  ///
  /// The email is the KDF salt (lowercased + trimmed) so the derivation is
  /// reproducible on a fresh device before anything has been downloaded.
  /// Runs in a background isolate.
  Future<({String authPassword, String vaultPassword})> deriveAccountKeys({
    required String email,
    required String password,
  }) async {
    return Isolate.run(() async {
      final normalizedEmail = email.trim().toLowerCase();
      final emailHash = await Sha256().hash(utf8.encode(normalizedEmail));

      final algorithm = Argon2id(
        memory: 65536,
        iterations: 2,
        parallelism: 1,
        hashLength: 32,
      );
      final stretched = await algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: emailHash.bytes,
      );
      final stretchedKey = SecretKey(await stretched.extractBytes());

      final hmac = Hmac.sha256();
      final auth = await hmac.calculateMac(
        utf8.encode('account:auth:v1'),
        secretKey: stretchedKey,
      );
      final vault = await hmac.calculateMac(
        utf8.encode('account:vault:v1'),
        secretKey: stretchedKey,
      );

      return (
        authPassword: base64Encode(auth.bytes),
        vaultPassword: base64Encode(vault.bytes),
      );
    });
  }

  // ──────────────────────────────────────────────────────────
  // AES-GCM — Vault encryption
  // ──────────────────────────────────────────────────────────

  /// Encrypt [plaintext] with AES-256-GCM using [key].
  @override
  Future<({Uint8List ciphertext, Uint8List iv})> encrypt({
    required String plaintext,
    required Uint8List key,
  }) async {
    final algorithm = AesGcm.with256bits();

    final secretBox = await algorithm.encryptString(
      plaintext,
      secretKey: SecretKey(key),
    );

    return (
      ciphertext: Uint8List.fromList(secretBox.concatenation(nonce: false)),
      iv: Uint8List.fromList(secretBox.nonce),
    );
  }

  /// Decrypt [ciphertext] with AES-256-GCM using [key] and [iv].
  @override
  Future<String> decrypt({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List iv,
  }) async {
    final algorithm = AesGcm.with256bits();

    final macLength = algorithm.macAlgorithm.macLength;
    final encryptedBytes = ciphertext.sublist(0, ciphertext.length - macLength);
    final macBytes = ciphertext.sublist(ciphertext.length - macLength);

    final secretBox = SecretBox(
      encryptedBytes,
      nonce: iv,
      mac: Mac(macBytes),
    );

    return algorithm.decryptString(
      secretBox,
      secretKey: SecretKey(key),
    );
  }

  /// Generate a fresh random 256-bit key for encrypting a single attachment.
  Uint8List generateFileKey() => _secureRandomBytes(32);

  /// Encrypt raw bytes with AES-256-GCM using [key] (attachment blobs). The
  /// returned ciphertext includes the GCM auth tag, matching [decryptBytes].
  Future<({Uint8List ciphertext, Uint8List iv})> encryptBytes({
    required Uint8List data,
    required Uint8List key,
  }) async {
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(data, secretKey: SecretKey(key));
    return (
      ciphertext: Uint8List.fromList(secretBox.concatenation(nonce: false)),
      iv: Uint8List.fromList(secretBox.nonce),
    );
  }

  /// Decrypt AES-256-GCM [ciphertext] (tag appended) with [key] and [iv].
  /// Throws on tampering (auth failure).
  Future<Uint8List> decryptBytes({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List iv,
  }) async {
    final algorithm = AesGcm.with256bits();
    final macLength = algorithm.macAlgorithm.macLength;
    final encryptedBytes = ciphertext.sublist(0, ciphertext.length - macLength);
    final macBytes = ciphertext.sublist(ciphertext.length - macLength);

    final secretBox = SecretBox(
      encryptedBytes,
      nonce: iv,
      mac: Mac(macBytes),
    );
    final clear = await algorithm.decrypt(secretBox, secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
  }

  // ──────────────────────────────────────────────────────────
  // HMAC-SHA256 — Identity derivation
  // ──────────────────────────────────────────────────────────

  /// Compute HMAC-SHA256(key, message) and return raw bytes.
  @override
  Future<Uint8List> hmacSha256({
    required Uint8List key,
    required String message,
  }) async {
    final algorithm = Hmac.sha256();
    final mac = await algorithm.calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(mac.bytes);
  }

  /// Derive the local vault encryption key from the master seed.
  ///
  /// key = HMAC-SHA256(masterSeed, "vault:v1")
  ///
  /// Always derivable from the locally-stored master seed — no password needed.
  /// Domain-separated with "vault:v1" to prevent key reuse across contexts.
  Future<Uint8List> deriveLocalVaultKey(Uint8List masterSeed) =>
      hmacSha256(key: masterSeed, message: 'vault:v1');

  /// Derive the full server identity from the master seed and host.
  ///
  /// Returns the Ed25519 keypair (for auth/signing) and the stable ID (for
  /// bans). When [serverId] is given the derivation is **scoped to that server**,
  /// so multiple servers sharing one Supabase host (project) each get a distinct
  /// SIWS identity — without it, two servers in one project would collide on
  /// `auth.uid()`. [serverId] is null only for the central host (one identity
  /// per host); that path is unchanged, preserving existing central keys.
  /// - childSeed = HMAC-SHA256(masterSeed, "<host>[:<serverId>]:<version>")
  /// - stableId  = HMAC-SHA256(masterSeed, "<host>[:<serverId>]:identity")
  Future<ServerIdentity> deriveServerIdentity({
    required Uint8List masterSeed,
    required String host,
    String? serverId,
    String version = 'v1',
  }) async {
    final scope = serverId == null ? host : '$host:$serverId';

    // Derive child seed → Ed25519 keypair
    final childSeed = await hmacSha256(
      key: masterSeed,
      message: '$scope:$version',
    );

    final ed = Ed25519();
    final keyPair = await ed.newKeyPairFromSeed(childSeed);
    final publicKey = await keyPair.extractPublicKey();

    // Derive stable ID
    final stableIdBytes = await hmacSha256(
      key: masterSeed,
      message: '$scope:identity',
    );

    return ServerIdentity(
      keyPair: keyPair,
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
      stableId: toBase64(stableIdBytes),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Ed25519 — Sign-in-with-Web3 (SIWS) login signing
  // ──────────────────────────────────────────────────────────

  /// Build and sign a Sign-in-with-Solana (SIWS) message for [domain]/[uri]
  /// with an Ed25519 keypair. The base58 of the public key is the "Solana
  /// address" GoTrue keys the identity on. Returns the exact message that was
  /// signed plus the base64 signature — both posted to the `login` function.
  ///
  /// `Chain ID: solana:mainnet` and the base64 signature encoding are required
  /// by GoTrue's web3 grant (verified against the local stack — see auth.md).
  Future<({String message, String signatureBase64})> signSiws({
    required SimpleKeyPair keyPair,
    required Uint8List publicKeyBytes,
    required String domain,
    required String uri,
  }) async {
    final address = toBase58(publicKeyBytes);
    final nonce = toBase64(_secureRandomBytes(12))
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final issuedAt = DateTime.now().toUtc().toIso8601String();

    final message = '$domain wants you to sign in with your Solana account:\n'
        '$address\n'
        '\n'
        'Sign in to Rift.\n'
        '\n'
        'URI: $uri\n'
        'Version: 1\n'
        'Chain ID: solana:mainnet\n'
        'Nonce: $nonce\n'
        'Issued At: $issuedAt';

    final ed = Ed25519();
    final signature = await ed.sign(utf8.encode(message), keyPair: keyPair);
    return (
      message: message,
      signatureBase64: toBase64(Uint8List.fromList(signature.bytes)),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────

  static String toBase64(Uint8List bytes) => base64Encode(bytes);

  static Uint8List fromBase64(String b64) =>
      Uint8List.fromList(base64Decode(b64));

  static const _b58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// Base58 (Bitcoin/Solana alphabet) encode — used for the SIWS address.
  static String toBase58(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    var intVal = BigInt.zero;
    for (final b in bytes) {
      intVal = (intVal << 8) | BigInt.from(b);
    }
    final buffer = StringBuffer();
    final base = BigInt.from(58);
    while (intVal > BigInt.zero) {
      final rem = (intVal % base).toInt();
      intVal = intVal ~/ base;
      buffer.write(_b58Alphabet[rem]);
    }
    // Leading zero bytes → leading '1's.
    for (final b in bytes) {
      if (b == 0) {
        buffer.write('1');
      } else {
        break;
      }
    }
    return buffer.toString().split('').reversed.join();
  }
}



