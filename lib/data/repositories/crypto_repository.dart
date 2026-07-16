import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../classes/server_identity.dart';

export '../classes/server_identity.dart';

/// Repository wrapping all cryptographic operations.
///
/// Uses the `cryptography` package for Argon2id, AES-GCM, HMAC-SHA256,
/// Ed25519, and secure random generation.
class CryptoRepository {
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

  // ──────────────────────────────────────────────────────────
  // HMAC-SHA256 — Identity derivation
  // ──────────────────────────────────────────────────────────

  /// Compute HMAC-SHA256(key, message) and return raw bytes.
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
  /// Returns the Ed25519 keypair (for auth) and the stable ID (for bans).
  /// - childSeed = HMAC-SHA256(masterSeed, "host:version")
  /// - stableId  = HMAC-SHA256(masterSeed, "host:identity")
  Future<ServerIdentity> deriveServerIdentity({
    required Uint8List masterSeed,
    required String host,
    String version = 'v1',
  }) async {
    // Derive child seed → Ed25519 keypair
    final childSeed = await hmacSha256(
      key: masterSeed,
      message: '$host:$version',
    );

    final ed = Ed25519();
    final keyPair = await ed.newKeyPairFromSeed(childSeed);
    final publicKey = await keyPair.extractPublicKey();

    // Derive stable ID
    final stableIdBytes = await hmacSha256(
      key: masterSeed,
      message: '$host:identity',
    );

    return ServerIdentity(
      keyPair: keyPair,
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
      stableId: toBase64(stableIdBytes),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Ed25519 — Challenge-response signing
  // ──────────────────────────────────────────────────────────

  /// Sign a challenge message with an Ed25519 keypair.
  ///
  /// The message format is "nonce@host" as specified in auth.md.
  Future<Uint8List> signChallenge({
    required SimpleKeyPair keyPair,
    required String nonce,
    required String host,
  }) async {
    final message = '$nonce@$host';
    final ed = Ed25519();
    final signature = await ed.sign(
      utf8.encode(message),
      keyPair: keyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }

  // ──────────────────────────────────────────────────────────
  // Ed25519 — Key rotation signing
  // ──────────────────────────────────────────────────────────

  /// Sign a key rotation payload with the OLD keypair.
  ///
  /// Message format: "rotate:<newPublicKeyBase64>@<nonce>@<host>"
  /// The nonce is a server-issued challenge that prevents replay attacks.
  /// The server verifies this using the old public key, then replaces it
  /// with the new one.
  Future<Uint8List> signRotation({
    required SimpleKeyPair oldKeyPair,
    required Uint8List newPublicKeyBytes,
    required String nonce,
    required String host,
  }) async {
    final newPubB64 = toBase64(newPublicKeyBytes);
    final message = 'rotate:$newPubB64@$nonce@$host';
    final ed = Ed25519();
    final signature = await ed.sign(
      utf8.encode(message),
      keyPair: oldKeyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────

  static String toBase64(Uint8List bytes) => base64Encode(bytes);

  static Uint8List fromBase64(String b64) =>
      Uint8List.fromList(base64Decode(b64));
}



