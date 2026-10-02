import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/backup_file.dart';
import 'package:rift/data/classes/encrypted_seed.dart';
import 'package:rift/data/classes/encrypted_vault.dart';
import 'package:rift/data/repositories/secure_storage_repository.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// Secure storage holding a master seed and nothing else.
class _SeedStorage extends SecureStorageRepository {
  final String seed;
  _SeedStorage(this.seed);

  @override
  Future<String?> getMasterSeed() async => seed;

  @override
  Future<String?> getPendingRecoveryKey() async => null;
}

String _seed(int fill) =>
    CryptoRepository.toBase64(Uint8List(32)..fillRange(0, 32, fill));

/// A backup whose vault blob is sealed under [seedB64]'s vault key — the part
/// that says whose it is. The seed blob is never opened by the check.
Future<String> _backupOf(String seedB64) async {
  final crypto = CryptoRepository();
  final key = await crypto.deriveLocalVaultKey(
    CryptoRepository.fromBase64(seedB64),
  );
  final sealed = await crypto.encrypt(
    plaintext: '{"joined_servers":[]}',
    key: key,
  );
  return BackupFile(
    version: BackupFile.currentVersion,
    seed: const EncryptedSeed(ciphertext: 'AA==', iv: 'AA==', salt: 'AA=='),
    vault: EncryptedVault(
      ciphertext: CryptoRepository.toBase64(sealed.ciphertext),
      iv: CryptoRepository.toBase64(sealed.iv),
    ),
  ).toJsonString();
}

void main() {
  // F-21: signing a device back in to the account it had backed itself up to
  // asked "Two identities — keep cloud or keep this device" about one identity.
  test('a backup of this seed is this vault', () async {
    final vault = VaultCubit(storage: _SeedStorage(_seed(1)));
    await vault.checkVaultStatus();

    expect(await vault.isBackupOfThisVault(await _backupOf(_seed(1))), isTrue);
    await vault.close();
  });

  test('a backup of another seed is not', () async {
    final vault = VaultCubit(storage: _SeedStorage(_seed(1)));
    await vault.checkVaultStatus();

    expect(await vault.isBackupOfThisVault(await _backupOf(_seed(2))), isFalse);
    await vault.close();
  });

  test('nor is something that is not a backup at all', () async {
    final vault = VaultCubit(storage: _SeedStorage(_seed(1)));
    await vault.checkVaultStatus();

    expect(await vault.isBackupOfThisVault('{"version":2}'), isFalse);
    await vault.close();
  });
}
