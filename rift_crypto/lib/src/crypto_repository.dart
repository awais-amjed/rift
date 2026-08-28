import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'chat_identity.dart';
import 'message_envelope.dart';
import 'server_identity.dart';
import 'wrapped_key.dart';

// Re-exported so `import 'crypto_repository.dart'` still hands over the types
// its methods return. `rift_crypto.dart` is the package's front door and
// exports the same set; this keeps the file honest on its own.
export 'chat_identity.dart';
export 'message_envelope.dart';
export 'server_identity.dart';
export 'wrapped_key.dart';

part 'crypto_repository_chat.dart';
part 'crypto_repository_command.dart';
part 'crypto_repository_identity.dart';

/// Repository wrapping all cryptographic operations.
///
/// Uses the `cryptography` package for Argon2id, AES-GCM, HMAC-SHA256,
/// Ed25519, X25519, and secure random generation. This file holds the
/// primitives — random, Argon2id key derivation, AES-GCM. Identity and login
/// crypto lives in the `_IdentityCryptoMixin` part, chat/messaging crypto in
/// `_ChatCryptoMixin`.
///
/// `_IdentityCryptoMixin` must come first: it supplies the concrete
/// `hmacSha256` that `_ChatCryptoMixin` declares abstract.
class CryptoRepository
    with _IdentityCryptoMixin, _ChatCryptoMixin, _CommandCryptoMixin {
  /// The derivation version of the X25519 chat identity, everywhere.
  ///
  /// Pinned at v1 and deliberately *not* following the Ed25519 auth key's
  /// rotation version: rotating the chat identity would make every channel key
  /// ever wrapped to the old one unreadable. Extending rotation to chat keys is
  /// a designed flow of its own (re-wrap on rotate), never an implicit
  /// consequence of rotating the login key.
  static const String chatIdentityVersion = 'v1';

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

  /// True when compiled for the web.
  ///
  /// The same trick `kIsWeb` uses, spelled out here rather than imported:
  /// dart2js has one number type, so `0` and `0.0` really are identical there
  /// and the compiler folds this to a constant. Taking it from
  /// `package:flutter/foundation.dart` instead would pull Flutter into the
  /// data layer and break the pure-Dart test scripts.
  static const bool _isWeb = identical(0, 0.0);

  /// Runs [work] off the UI thread where there is one to get off.
  ///
  /// Argon2id at 64 MiB is a deliberate second of CPU, so on native it goes to
  /// an isolate. The web has none — `dart:isolate` imports fine under dart2js
  /// and then throws `Unsupported operation` the moment [Isolate.run] is
  /// called, which is how vault creation failed there. Flutter's `compute`
  /// would not have helped: on the web it runs inline on the main thread too.
  /// So the honest thing is to await it directly and wear the jank.
  ///
  /// A web worker would fix the jank properly, and is worth doing if the
  /// freeze is felt — see TODO.md.
  static Future<T> _derive<T>(Future<T> Function() work) =>
      _isWeb ? work() : Isolate.run(work);

  /// Derive a 256-bit Vault Key from [password] + [salt] using Argon2id.
  ///
  /// Off the UI thread where the platform has isolates — see [_derive].
  Future<Uint8List> deriveVaultKey({
    required String password,
    required Uint8List salt,
    int memoryKiB = 65536,
    int iterations = 2,
    int parallelism = 1,
  }) async {
    return _derive(() async {
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
  /// Off the UI thread where the platform has isolates — see [_derive].
  Future<({String authPassword, String vaultPassword})> deriveAccountKeys({
    required String email,
    required String password,
  }) async {
    return _derive(() async {
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

    final secretBox = SecretBox(encryptedBytes, nonce: iv, mac: Mac(macBytes));

    return algorithm.decryptString(secretBox, secretKey: SecretKey(key));
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

    final secretBox = SecretBox(encryptedBytes, nonce: iv, mac: Mac(macBytes));
    final clear = await algorithm.decrypt(secretBox, secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
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
