import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
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
  APIResponse uploadAnswer = APIResponse.success(null);

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
    return uploadAnswer;
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

/// A vault that remembers which password its seed blob is currently under, so
/// a rollback is observable rather than merely claimed.
class _FakeVault extends VaultCubit {
  String wrappedUnder;
  bool rewrapFails = false;
  final rewraps = <({String from, String to})>[];

  _FakeVault({required this.wrappedUnder});

  @override
  Future<bool> verifyVaultPassword(String password) async =>
      password == wrappedUnder;

  @override
  Future<({bool success, String? error})> changeVaultPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (rewrapFails) return (success: false, error: 'nope');
    if (oldPassword != wrappedUnder) {
      return (success: false, error: 'Wrong password');
    }
    rewraps.add((from: oldPassword, to: newPassword));
    wrappedUnder = newPassword;
    return (success: true, error: null);
  }

  @override
  Future<({bool success, String? content, String? error})>
  exportBackup() async => (success: true, content: '{}', error: null);
}

/// One typed password stands behind two things that can fail independently:
/// the verifier GoTrue stores, and the key wrapping the master seed. The
/// failure worth designing against is the one where they end up disagreeing —
/// an account you can sign in to holding a backup it cannot open.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final crypto = CryptoRepository();
  const email = 'someone@example.com';
  const oldTyped = 'old-password';
  const newTyped = 'new-password-here';

  late _FakeRepo repo;
  late _FakeVault vault;
  late SupabaseBackupCubit cubit;

  /// The vault-blob password for an account is the derived one, never what
  /// was typed — so the fixture has to be built the same way the app does.
  Future<String> vaultPasswordFor(String typed) async =>
      (await crypto.deriveAccountKeys(
        email: email,
        password: typed,
      )).vaultPassword;

  Future<void> signedIn() async {
    vault = _FakeVault(wrappedUnder: await vaultPasswordFor(oldTyped));
    repo = _FakeRepo();
    cubit = SupabaseBackupCubit(vaultCubit: vault, repo: repo);
    cubit.emit(const SupabaseBackupState(isSignedIn: true, email: email));
  }

  tearDown(() async {
    await cubit.close();
    await vault.close();
  });

  group('proving the current password', () {
    test('a wrong one never costs an email', () async {
      await signedIn();
      await cubit.beginPasswordChange(currentPassword: 'not-it');

      expect(repo.codesSent, 0, reason: 'no email for a failed guess');
      expect(cubit.state.passwordChange, PasswordChangeStage.idle);
      expect(cubit.state.error, contains('not your current password'));
    });

    test('the right one asks for a code', () async {
      await signedIn();
      await cubit.beginPasswordChange(currentPassword: oldTyped);

      expect(repo.codesSent, 1);
      expect(cubit.state.passwordChange, PasswordChangeStage.enterCode);
      expect(cubit.state.error, isNull);
    });

    test('it is checked against the blob, not the typed string', () async {
      // The seed is wrapped under KDF(typed, "vault"). Handing the raw typed
      // password to the check would pass here and fail at the moment it
      // mattered.
      await signedIn();
      expect(await vault.verifyVaultPassword(oldTyped), isFalse);
      await cubit.beginPasswordChange(currentPassword: oldTyped);
      expect(cubit.state.passwordChange, PasswordChangeStage.enterCode);
    });

    test('a refused email leaves nothing half-started', () async {
      await signedIn();
      repo.codeAnswer = APIResponse.error('rate limited');
      await cubit.beginPasswordChange(currentPassword: oldTyped);

      expect(cubit.state.passwordChange, PasswordChangeStage.idle);
      expect(cubit.state.error, 'rate limited');
      // And the proved password is forgotten, so submitting now is refused.
      await cubit.submitPasswordChange(newPassword: newTyped, code: '1234');
      expect(vault.rewraps, isEmpty);
    });

    test('privacy mode has no address, so it asks for no code', () async {
      vault = _FakeVault(wrappedUnder: oldTyped);
      repo = _FakeRepo();
      cubit = SupabaseBackupCubit(vaultCubit: vault, repo: repo);
      cubit.emit(const SupabaseBackupState(isSignedIn: false));

      await cubit.beginPasswordChange(currentPassword: oldTyped);

      expect(repo.codesSent, 0);
      expect(cubit.state.passwordChange, PasswordChangeStage.enterNew);
    });
  });

  group('setting the new password', () {
    test('sends the derived verifier, never what was typed', () async {
      await signedIn();
      await cubit.beginPasswordChange(currentPassword: oldTyped);
      await cubit.submitPasswordChange(newPassword: newTyped, code: '12345678');

      final expected = (await crypto.deriveAccountKeys(
        email: email,
        password: newTyped,
      )).authPassword;

      expect(repo.sentPassword, expected);
      expect(repo.sentPassword, isNot(newTyped));
      expect(repo.sentNonce, '12345678');
    });

    test('rewraps the seed and uploads the result', () async {
      await signedIn();
      await cubit.beginPasswordChange(currentPassword: oldTyped);
      await cubit.submitPasswordChange(newPassword: newTyped, code: '12345678');

      expect(vault.rewraps.length, 1);
      expect(vault.wrappedUnder, await vaultPasswordFor(newTyped));
      // Until the upload lands, a restore elsewhere would still want the old
      // password.
      expect(repo.uploads, 1);
      expect(cubit.state.passwordChange, PasswordChangeStage.idle);
    });

    test('a rejected code puts the seed back where it was', () async {
      await signedIn();
      final before = vault.wrappedUnder;
      await cubit.beginPasswordChange(currentPassword: oldTyped);

      repo.updateAnswer = APIResponse.error('Invalid nonce');
      await cubit.submitPasswordChange(newPassword: newTyped, code: '00000000');

      // This is the whole point of the ordering. Leaving the local blob under
      // the new password after GoTrue refused would give an account whose
      // password signs in fine and opens nothing.
      expect(vault.wrappedUnder, before);
      expect(vault.rewraps.length, 2, reason: 'forward, then back');
      expect(vault.rewraps.last.to, before);
      expect(repo.uploads, 0, reason: 'nothing to publish');
      expect(cubit.state.error, 'Invalid nonce');
    });

    test('a local rewrap failure never reaches the server', () async {
      await signedIn();
      await cubit.beginPasswordChange(currentPassword: oldTyped);

      vault.rewrapFails = true;
      await cubit.submitPasswordChange(newPassword: newTyped, code: '12345678');

      expect(repo.sentPassword, isNull);
      expect(repo.uploads, 0);
    });

    test(
      'submitting without having proved the old password is refused',
      () async {
        await signedIn();
        await cubit.submitPasswordChange(
          newPassword: newTyped,
          code: '12345678',
        );

        expect(vault.rewraps, isEmpty);
        expect(repo.sentPassword, isNull);
        expect(cubit.state.error, contains('Start again'));
      },
    );

    test('cancelling forgets the proved password', () async {
      await signedIn();
      await cubit.beginPasswordChange(currentPassword: oldTyped);
      cubit.cancelPasswordChange();

      expect(cubit.state.passwordChange, PasswordChangeStage.idle);
      await cubit.submitPasswordChange(newPassword: newTyped, code: '12345678');
      expect(vault.rewraps, isEmpty);
    });

    test('privacy mode changes the blob and touches no server', () async {
      vault = _FakeVault(wrappedUnder: oldTyped);
      repo = _FakeRepo();
      cubit = SupabaseBackupCubit(vaultCubit: vault, repo: repo);
      cubit.emit(const SupabaseBackupState(isSignedIn: false));

      await cubit.beginPasswordChange(currentPassword: oldTyped);
      await cubit.submitPasswordChange(newPassword: newTyped);

      // No account, so the typed password guards the seed directly.
      expect(vault.wrappedUnder, newTyped);
      expect(repo.sentPassword, isNull);
      expect(repo.uploads, 0);
      expect(cubit.state.successMessage, 'Password changed.');
    });
  });
}
