import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/backup_file.dart';
import 'package:rift/data/classes/stored_vault.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/repositories/secure_storage_repository.dart';
import 'package:rift/data/repositories/supabase_backup_repository.dart';
import 'package:rift/logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift_crypto/rift_crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

class _MemoryHydrated implements Storage {
  final Map<String, dynamic> _data = {};
  @override
  dynamic read(String key) => _data[key];
  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
  @override
  Future<void> clear() async => _data.clear();
  @override
  Future<void> close() async {}
}

/// The platform plugin, in memory, so the real [SecureStorageRepository] —
/// its journal included — is what runs.
class _MemSecure implements FlutterSecureStorage {
  final Map<String, String> data;
  bool failReads = false;

  _MemSecure([Map<String, String>? data]) : data = data ?? {};

  /// Another device holding everything this one does.
  _MemSecure copy() => _MemSecure({...data});

  @override
  dynamic noSuchMethod(Invocation i) {
    final key = i.namedArguments[#key] as String?;
    switch (i.memberName) {
      case #read:
        if (failReads) {
          return Future<String?>.error(PlatformException(code: 'locked'));
        }
        return Future<String?>.value(data[key]);
      case #write:
        final value = i.namedArguments[#value] as String?;
        value == null ? data.remove(key) : data[key!] = value;
        return Future<void>.value();
      case #delete:
        data.remove(key);
        return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

class _Repo implements SupabaseBackupRepository {
  String? cloud;
  int uploads = 0;

  @override
  Future<APIResponse> downloadBackup() async => APIResponse.success(cloud);

  @override
  Future<APIResponse> uploadBackup(String backupJson) async {
    uploads++;
    cloud = backupJson;
    return APIResponse.success(null);
  }

  @override
  User? get currentUser => null;
  @override
  bool get isSignedIn => false;
  @override
  Stream<AuthState> get authChanges => const Stream.empty();

  @override
  noSuchMethod(Invocation invocation) => throw UnsupportedError(
    '${invocation.memberName} is not part of this test',
  );
}

const _password = 'a-good-long-password';
const _email = 'someone@example.com';

Future<VaultCubit> _vaultOn(_MemSecure mem) async {
  final vault = VaultCubit(storage: SecureStorageRepository(storage: mem));
  await vault.checkVaultStatus();
  return vault;
}

/// A device with a vault of its own, its recovery key written down.
Future<(VaultCubit, _MemSecure)> _newDevice({
  String password = _password,
  String? accountEmail,
}) async {
  final mem = _MemSecure();
  final vault = await _vaultOn(mem);
  await vault.createVault(password, accountEmail: accountEmail);
  await vault.acknowledgeRecoveryKey();
  return (vault, mem);
}

Future<String> _export(VaultCubit vault) async =>
    (await vault.exportBackup()).content!;

SupabaseBackupCubit _signedIn(VaultCubit vault, _Repo repo) {
  final cubit = SupabaseBackupCubit(vaultCubit: vault, repo: repo)
    ..setMergeCloudServers(
      (_) => (railChanged: false, cloudStale: false, joined: const []),
    );
  cubit.emit(const SupabaseBackupState(isSignedIn: true, email: _email));
  return cubit;
}

/// The vault, sign-in and backup review of Nov 22 2026: each case here is a
/// way that review found to lose an identity or lock somebody out of one.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryHydrated());

  group("another identity's cloud backup", () {
    test('is never overwritten by an ordinary backup', () async {
      final (mine, _) = await _newDevice();
      final (theirs, _) = await _newDevice();
      final repo = _Repo()..cloud = await _export(theirs);
      final before = repo.cloud;
      final cubit = _signedIn(mine, repo);

      await cubit.saveBackupToCloud();
      expect(repo.uploads, 0);
      expect(repo.cloud, before);
      expect(cubit.state.cloudBackupConflict, isTrue);

      // After a restart the question is gone from memory; the next pull asks
      // it again rather than letting the next change upload.
      cubit.dismissPending();
      await cubit.pullFromCloud(thenPush: true);
      expect(cubit.state.cloudBackupConflict, isTrue);
      expect(repo.uploads, 0);

      // Choosing this device is the one thing that replaces it.
      await cubit.keepLocalVault();
      expect(repo.uploads, 1);
      expect(await mine.isBackupOfThisVault(repo.cloud!), isTrue);

      await cubit.close();
      await mine.close();
      await theirs.close();
    });

    test('stops "sign out of this device" from trusting it', () async {
      final (mine, _) = await _newDevice();
      final (theirs, _) = await _newDevice();
      final repo = _Repo()..cloud = await _export(theirs);
      final cubit = _signedIn(mine, repo);

      expect(await cubit.confirmCloudHoldsVault(), isFalse);

      // With nothing there yet, the check uploads and then proves it.
      repo.cloud = null;
      cubit.dismissPending();
      expect(await cubit.confirmCloudHoldsVault(), isTrue);

      await cubit.close();
      await mine.close();
      await theirs.close();
    });
  });

  group('wraps', () {
    test('a newer recovery key is adopted, and an older one is not '
        'put back', () async {
      final (desktop, desktopMem) = await _newDevice();
      final phone = await _vaultOn(desktopMem.copy());
      final phoneOld = await _export(phone);

      final replaced = await desktop.regenerateRecoveryKey(password: _password);
      expect(replaced.success, isTrue);
      await desktop.acknowledgeRecoveryKey();
      final desktopNew = await _export(desktop);

      // The desktop meets the phone's older backup: its own wins.
      expect(await desktop.syncWraps(phoneOld), WrapsSync.localNewer);

      // The phone meets the desktop's: it takes the new key's wrap.
      expect(await phone.syncWraps(desktopNew), WrapsSync.adopted);
      final carried = BackupFile.fromJsonString(await _export(phone)).recovery!;
      final opened = await phone.unwrapWithRecoveryKey(
        blob: carried,
        recoveryKey: replaced.key!,
      );
      expect(opened.masterSeedB64, phone.state.masterSeed);
      expect(await phone.syncWraps(desktopNew), WrapsSync.same);

      await desktop.close();
      await phone.close();
    });

    test('only wraps sealed under this seed count', () async {
      final (desktop, desktopMem) = await _newDevice();
      final phone = await _vaultOn(desktopMem.copy());
      final (stranger, _) = await _newDevice();
      await stranger.regenerateRecoveryKey(password: _password);

      // A backup of this vault carrying someone else's (newer) wraps, as a
      // central that wanted to take the recovery key away could serve.
      final forged = jsonDecode(await _export(desktop)) as Map<String, dynamic>;
      forged['wraps'] = (jsonDecode(await _export(stranger)) as Map)['wraps'];

      expect(
        await phone.syncWraps(jsonEncode(forged)),
        isNot(WrapsSync.adopted),
      );

      await desktop.close();
      await phone.close();
      await stranger.close();
    });
  });

  group('restoring a file', () {
    test('made on an account opens with the account password', () async {
      final crypto = CryptoRepository();
      final derived = (await crypto.deriveAccountKeys(
        email: _email,
        password: _password,
      )).vaultPassword;
      final (onAccount, _) = await _newDevice(
        password: derived,
        accountEmail: _email,
      );
      final file = await _export(onAccount);

      final fresh = await _vaultOn(_MemSecure());
      final typedOnly = await fresh.importBackup(
        jsonContent: file,
        password: _password,
      );
      expect(typedOnly.success, isFalse);

      final withEmail = await fresh.importBackup(
        jsonContent: file,
        password: _password,
        accountEmail: _email,
      );
      expect(withEmail.success, isTrue, reason: withEmail.error ?? '');
      expect(fresh.state.masterSeed, onAccount.state.masterSeed);
      expect(await fresh.seedWrapEmail(), _email);

      await onAccount.close();
      await fresh.close();
    });

    test('that is not a backup fails without leaving it busy', () async {
      final fresh = await _vaultOn(_MemSecure());
      final result = await fresh.importBackup(
        jsonContent: '{"version": 3}',
        password: _password,
      );
      expect(result.success, isFalse);
      expect(fresh.state.isProcessing, isFalse);
      await fresh.close();
    });

    test('from a newer Rift is refused, not misread', () async {
      final (device, _) = await _newDevice();
      final newer = jsonDecode(await _export(device)) as Map<String, dynamic>;
      newer['version'] = BackupFile.currentVersion + 1;

      final fresh = await _vaultOn(_MemSecure());
      final result = await fresh.importBackup(
        jsonContent: jsonEncode(newer),
        password: _password,
      );
      expect(result.success, isFalse);
      expect(result.error, contains('newer version'));
      expect(fresh.state.status, AuthStatus.fresh);

      await device.close();
      await fresh.close();
    });

    test('with no recovery key leaves none of the old one behind', () async {
      final mem = _MemSecure();
      final device = await _vaultOn(mem);
      await device.createVault(_password);
      expect(device.state.pendingRecoveryKey, isNotNull);

      final file = jsonDecode(await _export(device)) as Map<String, dynamic>;
      file.remove('recovery');
      final result = await device.importBackup(
        jsonContent: jsonEncode(file),
        password: _password,
      );
      expect(result.success, isTrue, reason: result.error ?? '');

      final storage = SecureStorageRepository(storage: mem);
      expect(await storage.getRecoverySeed(), isNull);
      expect(await storage.getPendingRecoveryKey(), isNull);
      expect(device.state.pendingRecoveryKey, isNull);
      await device.close();
    });
  });

  group('storage', () {
    test('a replace cut short is finished on the next start', () async {
      final (device, mem) = await _newDevice();
      final storage = SecureStorageRepository(storage: mem);
      final whole = StoredVault(
        masterSeed: CryptoRepository.toBase64(
          CryptoRepository().generateMasterSeed(),
        ),
        joinedServers: const [(url: 'rift.example.com', version: 'v1')],
        seed: (await storage.getEncryptedSeed())!,
        vault: (await storage.getEncryptedVault())!,
        recovery: null,
        pendingRecoveryKey: null,
        wrapsAt: 7,
        seedWrapEmail: null,
      );
      // Killed after the journal and before anything else was applied.
      mem.data['${SecureStorageRepository.namespacePrefix}vault_journal'] =
          jsonEncode(whole.toJson());

      final restarted = await _vaultOn(mem);
      expect(restarted.state.masterSeed, whole.masterSeed);
      expect(await storage.getRecoverySeed(), isNull);
      expect(await storage.getWrapsAt(), 7);
      expect(
        mem.data.containsKey(
          '${SecureStorageRepository.namespacePrefix}vault_journal',
        ),
        isFalse,
      );

      await device.close();
      await restarted.close();
    });

    test('a read that fails is unreadable, not "no vault"', () async {
      final (device, mem) = await _newDevice();
      final seed = device.state.masterSeed;
      mem.failReads = true;

      final restarted = await _vaultOn(mem);
      expect(restarted.state.status, AuthStatus.unreadable);
      expect(restarted.state.stillSettingUp, isTrue);

      // And a vault is never made over one that is there.
      mem.failReads = false;
      await restarted.createVault('another-password');
      expect(await SecureStorageRepository(storage: mem).getMasterSeed(), seed);

      await device.close();
      await restarted.close();
    });
  });

  test('the account password still changes the password after the '
      'session ended', () async {
    final crypto = CryptoRepository();
    final derived = (await crypto.deriveAccountKeys(
      email: _email,
      password: _password,
    )).vaultPassword;
    final (vault, _) = await _newDevice(
      password: derived,
      accountEmail: _email,
    );
    // Signed out elsewhere: no session, no email in state.
    final cubit = SupabaseBackupCubit(vaultCubit: vault, repo: _Repo());

    await cubit.beginPasswordChange(currentPassword: _password);
    expect(cubit.state.error, isNull);
    expect(cubit.state.passwordChange, PasswordChangeStage.enterNew);

    await cubit.close();
    await vault.close();
  });
}
