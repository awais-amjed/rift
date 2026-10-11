import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/encrypted_seed.dart';
import 'package:rift/data/repositories/supabase_backup_repository.dart';
import 'package:rift/logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift_crypto/rift_crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

class _MemoryStorage implements Storage {
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

class _FakeRepo implements SupabaseBackupRepository {
  APIResponse codeAnswer = APIResponse.success(null);
  APIResponse updateAnswer = APIResponse.success(null);

  int codesSent = 0;
  String? sentPassword;
  String? sentNonce;
  int uploads = 0;

  @override
  Future<APIResponse> sendReauthenticationCode() async {
    codesSent++;
    return codeAnswer;
  }

  @override
  Future<APIResponse> updatePassword({
    required String password,
    String? nonce,
  }) async {
    sentPassword = password;
    sentNonce = nonce;
    return updateAnswer;
  }

  @override
  Future<APIResponse> uploadBackup(String backupJson) async {
    uploads++;
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

/// A vault whose stored blob names the password it is under, and which counts
/// the recovery keys it mints.
class _FakeVault extends VaultCubit {
  EncryptedSeed blob;
  bool rewrapFails = false;
  int keysIssued = 0;

  _FakeVault({required String wrappedUnder})
    : blob = EncryptedSeed(ciphertext: wrappedUnder, iv: '', salt: '');

  String get wrappedUnder => blob.ciphertext;

  @override
  Future<({bool success, String? error})> rewrapSeed({
    required String newPassword,
  }) async {
    if (rewrapFails) return (success: false, error: 'nope');
    blob = EncryptedSeed(ciphertext: newPassword, iv: '', salt: '');
    return (success: true, error: null);
  }

  @override
  Future<EncryptedSeed?> storedSeedBlob() async => blob;

  @override
  Future<void> restoreSeedBlob(EncryptedSeed blob) async => this.blob = blob;

  @override
  Future<({bool success, String? error})> reissueRecoveryKey() async {
    keysIssued++;
    return (success: true, error: null);
  }

  @override
  Future<({bool success, String? content, String? error})>
  exportBackup() async => (success: true, content: '{}', error: null);
}

/// A forgotten password on a device signed in to the account: the code stands
/// in for the old password, since the seed is already in memory. The account's
/// password and the blob it has to open must still never disagree.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final crypto = CryptoRepository();
  const email = 'someone@example.com';
  const newTyped = 'new-password-here';
  const forgotten = 'derived-from-the-forgotten-one';

  late _FakeRepo repo;
  late _FakeVault vault;
  late SupabaseBackupCubit cubit;

  void signedIn() {
    vault = _FakeVault(wrappedUnder: forgotten);
    repo = _FakeRepo();
    cubit = SupabaseBackupCubit(vaultCubit: vault, repo: repo);
    cubit.emit(const SupabaseBackupState(isSignedIn: true, email: email));
  }

  tearDown(() async {
    await cubit.close();
    await vault.close();
  });

  test('asks for a code without asking for the password', () async {
    signedIn();
    await cubit.beginPasswordReset();

    expect(repo.codesSent, 1);
    expect(cubit.state.passwordChange, PasswordChangeStage.reset);
  });

  test('is not offered without an account', () async {
    vault = _FakeVault(wrappedUnder: forgotten);
    repo = _FakeRepo();
    cubit = SupabaseBackupCubit(vaultCubit: vault, repo: repo);
    cubit.emit(const SupabaseBackupState(isSignedIn: false));

    await cubit.beginPasswordReset();
    await cubit.submitPasswordReset(newPassword: newTyped, code: '123456');

    expect(repo.codesSent, 0);
    expect(vault.wrappedUnder, forgotten);
    expect(vault.keysIssued, 0);
  });

  test('sets the derived password, rewraps, mints a key, uploads', () async {
    signedIn();
    await cubit.beginPasswordReset();
    await cubit.submitPasswordReset(newPassword: newTyped, code: '123456');

    final keys = await crypto.deriveAccountKeys(
      email: email,
      password: newTyped,
    );
    expect(repo.sentPassword, keys.authPassword);
    expect(repo.sentNonce, '123456');
    expect(vault.wrappedUnder, keys.vaultPassword);
    expect(vault.keysIssued, 1);
    expect(repo.uploads, 1);
    expect(cubit.state.passwordChange, PasswordChangeStage.idle);
  });

  test('a refused code puts the old blob back and mints nothing', () async {
    signedIn();
    await cubit.beginPasswordReset();
    repo.updateAnswer = APIResponse.error('Invalid nonce');
    await cubit.submitPasswordReset(newPassword: newTyped, code: '000000');

    // The account still has the forgotten password, so the blob must still
    // open with it — or the next restore elsewhere opens nothing.
    expect(vault.wrappedUnder, forgotten);
    expect(
      vault.keysIssued,
      0,
      reason: 'the code was the proof; without it no key',
    );
    expect(repo.uploads, 0);
    expect(cubit.state.error, 'Invalid nonce');
  });

  test('a local rewrap failure never reaches the server', () async {
    signedIn();
    await cubit.beginPasswordReset();
    vault.rewrapFails = true;
    await cubit.submitPasswordReset(newPassword: newTyped, code: '123456');

    expect(repo.sentPassword, isNull);
    expect(vault.keysIssued, 0);
    expect(repo.uploads, 0);
  });
}
