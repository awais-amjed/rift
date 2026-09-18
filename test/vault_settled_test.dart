import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/repositories/secure_storage_repository.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// Secure storage that answers only when the test says so — the moment
/// between launch and the keyring replying is the whole subject here.
class _SlowStorage extends SecureStorageRepository {
  final seed = Completer<String?>();

  @override
  Future<String?> getMasterSeed() => seed.future;

  @override
  Future<String?> getPendingRecoveryKey() async => null;
}

void main() {
  final masterSeed = CryptoRepository.toBase64(Uint8List(32));

  // What went wrong at every cold start once the tokens had expired: the first
  // server calls re-logged in before the seed was read, and each one died on
  // a null check.
  test('an identity asked for while the vault is read waits for it', () async {
    final storage = _SlowStorage();
    final vault = VaultCubit(storage: storage);
    unawaited(vault.checkVaultStatus());

    final identity = vault.getIdentityForHost('example.test', serverId: 's1');
    storage.seed.complete(masterSeed);

    expect((await identity).publicKeyBytes, hasLength(32));
    await vault.close();
  });

  test('the chat identity waits the same way', () async {
    final storage = _SlowStorage();
    final vault = VaultCubit(storage: storage);
    unawaited(vault.checkVaultStatus());

    final identity = vault.getChatIdentityForHost('example.test');
    storage.seed.complete(masterSeed);

    await expectLater(identity, completes);
    await vault.close();
  });

  test('with no vault at all, it says so rather than a null check', () async {
    final storage = _SlowStorage();
    final vault = VaultCubit(storage: storage);
    unawaited(vault.checkVaultStatus());

    final identity = vault.getIdentityForHost('example.test', serverId: 's1');
    storage.seed.complete(null);

    await expectLater(identity, throwsStateError);
    expect(vault.state.status, AuthStatus.fresh);
    await vault.close();
  });

  test('once read, settling is immediate', () async {
    final storage = _SlowStorage()..seed.complete(masterSeed);
    final vault = VaultCubit(storage: storage);
    await vault.checkVaultStatus();

    expect((await vault.settled()).status, AuthStatus.unlocked);
    await vault.close();
  });
}
