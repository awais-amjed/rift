import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift_crypto/rift_crypto.dart';

import 'package:rift/data/classes/backup_file.dart';
import 'package:rift/data/classes/encrypted_seed.dart';
import 'package:rift/data/classes/encrypted_vault.dart';

/// The recovery key is a second door onto the master seed. These hold it to
/// the two things that makes true: that a key generated here opens the blob it
/// wrapped, and that a key typed back in imperfectly still does.
void main() {
  final crypto = CryptoRepository();

  group('a generated recovery key', () {
    test('is five groups of five from the unambiguous alphabet', () {
      for (var i = 0; i < 50; i++) {
        final key = crypto.generateRecoveryKey();
        expect(key, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{5}(-[0-9A-HJKMNP-TV-Z]{5}){4}$')));
        // The characters Crockford drops are the ones that get misread.
        expect(key.contains('I'), isFalse);
        expect(key.contains('L'), isFalse);
        expect(key.contains('O'), isFalse);
        expect(key.contains('U'), isFalse);
      }
    });

    test('does not repeat itself', () {
      final seen = {for (var i = 0; i < 200; i++) crypto.generateRecoveryKey()};
      expect(seen.length, 200);
    });

    test('spreads over the whole alphabet', () {
      // Guards the modulo-bias trap: a naive `nextInt(256) % 32` would make
      // the first symbols measurably more likely than the last.
      final counts = <String, int>{};
      for (var i = 0; i < 400; i++) {
        for (final c in crypto.generateRecoveryKey().replaceAll('-', '').split('')) {
          counts[c] = (counts[c] ?? 0) + 1;
        }
      }
      expect(counts.length, 32, reason: 'every symbol should appear');
      final expected = (400 * 25) / 32;
      for (final entry in counts.entries) {
        expect(
          entry.value,
          greaterThan(expected * 0.6),
          reason: '${entry.key} is under-represented',
        );
      }
    });
  });

  group('normalising what somebody typed', () {
    test('accepts the key exactly as shown', () {
      final key = crypto.generateRecoveryKey();
      expect(crypto.normalizeRecoveryKey(key), key.replaceAll('-', ''));
    });

    test('forgives lower case, spaces and missing dashes', () {
      const canonical = 'ABCDE12345FGHJK67890MNPQR';
      const shown = 'ABCDE-12345-FGHJK-67890-MNPQR';
      for (final typed in [
        shown,
        shown.toLowerCase(),
        canonical,
        'ABCDE 12345 FGHJK 67890 MNPQR',
        '  abcde-12345-fghjk-67890-mnpqr  ',
        'ABCDE_12345_FGHJK_67890_MNPQR',
      ]) {
        expect(crypto.normalizeRecoveryKey(typed), canonical, reason: typed);
      }
    });

    test('reads the confusable letters as the digits they look like', () {
      // Nothing generates an I, L or O — so seeing one means somebody typed
      // what they saw, and what they saw was a 1 or a 0.
      expect(crypto.normalizeRecoveryKey('ABCDE1234SFGHJK67890MNPQR'),
          crypto.normalizeRecoveryKey('ABCDEI234SFGHJK6789OMNPQR'));
    });

    test('rejects anything that is not a key, before spending Argon2id on it', () {
      expect(crypto.normalizeRecoveryKey(''), isNull);
      expect(crypto.normalizeRecoveryKey('too-short'), isNull);
      expect(crypto.normalizeRecoveryKey('ABCDE12345FGHJK67890MNPQRZ'), isNull);
      expect(crypto.normalizeRecoveryKey('ABCDE12345FGHJK67890MNPQ!'), isNull);
    });

    test('formatting round-trips with normalising', () {
      final key = crypto.generateRecoveryKey();
      final normalized = crypto.normalizeRecoveryKey(key)!;
      expect(crypto.formatRecoveryKey(normalized), key);
    });
  });

  group('wrapping the seed', () {
    test('the key opens what it wrapped, and a near miss does not', () async {
      final seed = CryptoRepository.toBase64(crypto.generateMasterSeed());
      final key = crypto.generateRecoveryKey();
      final salt = crypto.generateSalt();

      final wrapKey = await crypto.deriveVaultKey(
        password: crypto.normalizeRecoveryKey(key)!,
        salt: salt,
      );
      final wrapped = await crypto.encrypt(plaintext: seed, key: wrapKey);

      // Typed back sloppily — lower case, no dashes.
      final retyped = crypto.normalizeRecoveryKey(
        key.replaceAll('-', '').toLowerCase(),
      )!;
      final openKey = await crypto.deriveVaultKey(password: retyped, salt: salt);
      final opened = await crypto.decrypt(
        ciphertext: wrapped.ciphertext,
        key: openKey,
        iv: wrapped.iv,
      );
      expect(opened, seed);

      // A different key of the same shape must not.
      final wrongKey = await crypto.deriveVaultKey(
        password: crypto.normalizeRecoveryKey(crypto.generateRecoveryKey())!,
        salt: salt,
      );
      expect(
        () => crypto.decrypt(
          ciphertext: wrapped.ciphertext,
          key: wrongKey,
          iv: wrapped.iv,
        ),
        throwsA(anything),
      );
    });

    test('password and recovery blobs are independent doors on one seed',
        () async {
      // The property the whole design rests on: changing one wrapping does
      // not disturb the other, because the plaintext under both is the seed
      // and the seed never changes.
      final seed = CryptoRepository.toBase64(crypto.generateMasterSeed());

      final passSalt = crypto.generateSalt();
      final passKey = await crypto.deriveVaultKey(
        password: 'first-password',
        salt: passSalt,
      );
      final byPassword = await crypto.encrypt(plaintext: seed, key: passKey);

      final recKey = crypto.generateRecoveryKey();
      final recSalt = crypto.generateSalt();
      final recWrapKey = await crypto.deriveVaultKey(
        password: crypto.normalizeRecoveryKey(recKey)!,
        salt: recSalt,
      );
      final byRecovery = await crypto.encrypt(plaintext: seed, key: recWrapKey);

      // Re-wrap under a new password, as a password change does.
      final newSalt = crypto.generateSalt();
      final newPassKey = await crypto.deriveVaultKey(
        password: 'second-password',
        salt: newSalt,
      );
      final rewrapped = await crypto.encrypt(plaintext: seed, key: newPassKey);

      // Old password blob is dead; new one and the untouched recovery blob
      // both still open the same seed.
      expect(
        await crypto.decrypt(
          ciphertext: rewrapped.ciphertext,
          key: newPassKey,
          iv: rewrapped.iv,
        ),
        seed,
      );
      expect(
        await crypto.decrypt(
          ciphertext: byRecovery.ciphertext,
          key: recWrapKey,
          iv: byRecovery.iv,
        ),
        seed,
      );
      expect(byPassword.ciphertext, isNot(rewrapped.ciphertext));
    });
  });

  group('the backup file', () {
    EncryptedSeed seedBlob(String tag) =>
        EncryptedSeed(ciphertext: 'c$tag', iv: 'i$tag', salt: 's$tag');

    test('carries the recovery wrap through a round trip', () {
      final file = BackupFile(
        version: BackupFile.currentVersion,
        seed: seedBlob('pass'),
        vault: const EncryptedVault(ciphertext: 'cv', iv: 'iv'),
        recovery: seedBlob('rec'),
      );

      final back = BackupFile.fromJsonString(file.toJsonString());
      expect(back.recovery, isNotNull);
      expect(back.recovery!.ciphertext, 'crec');
      expect(back.recovery!.salt, 'srec');
      expect(back.seed.ciphertext, 'cpass');
    });

    test('a file written before recovery keys still loads', () {
      // v2 files are real and on people's disks. They mean "password only",
      // which is exactly what a null recovery blob says.
      final legacy = jsonEncode({
        'version': 2,
        'seed': seedBlob('pass').toJson(),
        'vault': const EncryptedVault(ciphertext: 'cv', iv: 'iv').toJson(),
      });

      final back = BackupFile.fromJsonString(legacy);
      expect(back.version, 2);
      expect(back.recovery, isNull);
      expect(back.seed.ciphertext, 'cpass');
    });

    test('omits the key entirely rather than writing a null', () {
      final file = BackupFile(
        version: BackupFile.currentVersion,
        seed: seedBlob('pass'),
        vault: const EncryptedVault(ciphertext: 'cv', iv: 'iv'),
      );
      expect(file.toJson().containsKey('recovery'), isFalse);
    });
  });
}
