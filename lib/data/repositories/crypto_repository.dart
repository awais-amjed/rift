import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Repository wrapping all cryptographic operations.
///
/// Uses the `cryptography` package for Argon2id, AES-GCM, and secure random
/// generation. Heavy KDF work runs inside an [Isolate] to keep the UI smooth.
class CryptoRepository {
  /// Generate a cryptographically secure 256-bit (32 byte) master seed.
  Uint8List generateMasterSeed() => _secureRandomBytes(32);

  /// Generate a cryptographically secure 256-bit (32 byte) salt.
  Uint8List generateSalt() => _secureRandomBytes(32);

  /// Fill [length] bytes with cryptographically secure random data.
  static Uint8List _secureRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  /// Derive a 256-bit Vault Key from [password] + [salt] using Argon2id.
  ///
  /// Runs in a background isolate to avoid blocking the UI.
  /// Params from auth.md: 64 MiB memory, 2 iterations, 1 parallelism.
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

  /// Encrypt [plaintext] with AES-256-GCM using [key].
  ///
  /// Returns a record of (ciphertext, iv) — both as raw bytes.
  /// A fresh random 12-byte IV is generated for every call.
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
  ///
  /// Returns the plaintext string.
  Future<String> decrypt({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List iv,
  }) async {
    final algorithm = AesGcm.with256bits();

    // AES-GCM concatenation (without nonce) = ciphertext + mac (16 bytes)
    // Split the last 16 bytes as the MAC tag
    final macLength = algorithm.macAlgorithm.macLength;
    final encryptedBytes = ciphertext.sublist(0, ciphertext.length - macLength);
    final macBytes = ciphertext.sublist(ciphertext.length - macLength);

    final secretBox = SecretBox(
      encryptedBytes,
      nonce: iv,
      mac: Mac(macBytes),
    );

    final plaintext = await algorithm.decryptString(
      secretBox,
      secretKey: SecretKey(key),
    );

    return plaintext;
  }

  /// Helper: encode bytes to base64.
  static String toBase64(Uint8List bytes) => base64Encode(bytes);

  /// Helper: decode base64 to bytes.
  static Uint8List fromBase64(String b64) =>
      Uint8List.fromList(base64Decode(b64));
}


