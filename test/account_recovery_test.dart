import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/repositories/supabase_backup_repository.dart';
import 'package:rift/logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/presentation/screens/settings/widgets/backup_content/change_password_panel.dart';
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
  APIResponse sendAnswer = APIResponse.success(null);
  APIResponse verifyAnswer = APIResponse.success(null);
  APIResponse updateAnswer = APIResponse.success(null);
  APIResponse downloadAnswer = APIResponse.success('{"backup":true}');

  final mailedTo = <String>[];
  String? verifiedToken;
  String? sentPassword;
  String? sentNonce;
  bool updateCalled = false;
  int uploads = 0;

  @override
  Future<APIResponse> sendPasswordRecovery({required String email}) async {
    mailedTo.add(email);
    return sendAnswer;
  }

  @override
  Future<APIResponse> verifyRecoveryCode({
    required String email,
    required String token,
  }) async {
    verifiedToken = token;
    return verifyAnswer;
  }

  @override
  Future<APIResponse> updatePassword({
    required String password,
    String? nonce,
  }) async {
    updateCalled = true;
    sentPassword = password;
    sentNonce = nonce;
    return updateAnswer;
  }

  @override
  Future<APIResponse> downloadBackup() async => downloadAnswer;

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

class _FakeVault extends VaultCubit {
  String? wrappedUnder;
  bool importSucceeds = true;
  String? importedWithRecoveryKey;
  String? rewrappedUnder;

  @override
  Future<({bool success, String? error})> importBackup({
    required String jsonContent,
    String? password,
    String? recoveryKey,
  }) async {
    importedWithRecoveryKey = recoveryKey;
    if (!importSucceeds) {
      return (success: false, error: 'That recovery key does not match');
    }
    return (success: true, error: null);
  }

  @override
  Future<({bool success, String? error})> rewrapSeed({
    required String newPassword,
  }) async {
    rewrappedUnder = newPassword;
    return (success: true, error: null);
  }

  @override
  Future<({bool success, String? error, String? key})> regenerateRecoveryKey({
    required String password,
  }) async {
    if (password != wrappedUnder) {
      return (success: false, error: 'Wrong password', key: null);
    }
    return (success: true, error: null, key: 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE');
  }

  @override
  Future<({bool success, String? content, String? error})>
  exportBackup() async => (success: true, content: '{}', error: null);
}

/// Recovery is two halves that only work together: a code recovers the
/// account, and the recovery key recovers the vault. Nothing on any server
/// can do the second one.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final crypto = CryptoRepository();
  const email = 'someone@example.com';
  const newPassword = 'a-brand-new-password';
  const goodKey = 'ABCDE-12345-FGHJK-67890-MNPQR';

  late _FakeRepo repo;
  late _FakeVault vault;
  late SupabaseBackupCubit cubit;

  setUp(() {
    repo = _FakeRepo();
    vault = _FakeVault();
    cubit = SupabaseBackupCubit(vaultCubit: vault, repo: repo);
  });

  tearDown(() async {
    await cubit.close();
    await vault.close();
  });

  group('asking for a code', () {
    test('opening the flow sends nothing yet', () {
      cubit.startAccountRecovery(email: email);
      expect(cubit.state.accountRecovery, AccountRecoveryStage.enterEmail);
      // The address on a sign-in form is often half-typed; mailing it before
      // it is confirmed would spend a rate limit on a guess.
      expect(repo.mailedTo, isEmpty);
      expect(cubit.state.email, email);
    });

    test('a malformed address never reaches the server', () async {
      cubit.startAccountRecovery();
      await cubit.beginAccountRecovery(email: 'not-an-address');
      expect(repo.mailedTo, isEmpty);
      expect(cubit.state.error, contains('valid email'));
    });

    test('says nothing about whether the account exists', () async {
      await cubit.beginAccountRecovery(email: email);
      expect(repo.mailedTo, [email]);
      expect(cubit.state.accountRecovery, AccountRecoveryStage.enterCode);
      expect(cubit.state.successMessage, startsWith('If $email'));
    });
  });

  group('finishing', () {
    Future<void> atCodeStage() => cubit.beginAccountRecovery(email: email);

    test(
      'a key of the wrong shape is refused before the code is spent',
      () async {
        await atCodeStage();
        await cubit.completeAccountRecovery(
          code: '12345678',
          recoveryKey: 'nonsense',
          newPassword: newPassword,
        );

        expect(repo.verifiedToken, isNull, reason: 'code not burned on a typo');
        expect(
          cubit.state.error,
          contains('does not look like a recovery key'),
        );
      },
    );

    test('sets the derived verifier, with no nonce', () async {
      await atCodeStage();
      await cubit.completeAccountRecovery(
        code: '12345678',
        recoveryKey: goodKey,
        newPassword: newPassword,
      );

      final expected = (await crypto.deriveAccountKeys(
        email: email,
        password: newPassword,
      )).authPassword;

      expect(repo.verifiedToken, '12345678');
      expect(repo.sentPassword, expected);
      expect(repo.sentPassword, isNot(newPassword));
      // Verifying the code *is* the proof; GoTrue wants a nonce only when the
      // session predates the request.
      expect(repo.sentNonce, isNull);
    });

    test(
      'opens the backup with the key, then rewraps under the new password',
      () async {
        await atCodeStage();
        await cubit.completeAccountRecovery(
          code: '12345678',
          recoveryKey: goodKey,
          newPassword: newPassword,
        );

        final keys = await crypto.deriveAccountKeys(
          email: email,
          password: newPassword,
        );

        expect(vault.importedWithRecoveryKey, goodKey);
        // Without the rewrap the imported blob would still be under the
        // forgotten password, and the next sign-in would need recovery again.
        expect(vault.rewrappedUnder, keys.vaultPassword);
        expect(repo.uploads, 1);
        expect(cubit.state.isSignedIn, isTrue);
        expect(cubit.state.accountRecovery, AccountRecoveryStage.idle);
      },
    );

    test('a wrong code stops before the password is touched', () async {
      await atCodeStage();
      repo.verifyAnswer = APIResponse.error('Token has expired');

      await cubit.completeAccountRecovery(
        code: '00000000',
        recoveryKey: goodKey,
        newPassword: newPassword,
      );

      expect(repo.updateCalled, isFalse);
      expect(vault.importedWithRecoveryKey, isNull);
      expect(cubit.state.error, 'Token has expired');
    });

    test(
      'a wrong recovery key leaves the account usable to try again',
      () async {
        await atCodeStage();
        vault.importSucceeds = false;

        await cubit.completeAccountRecovery(
          code: '12345678',
          recoveryKey: goodKey,
          newPassword: newPassword,
        );

        // The password is already set by this point and that is deliberate: the
        // key cannot be checked without downloading the backup, and the backup
        // needs a session. Being signed in is what makes a second attempt
        // possible.
        expect(cubit.state.isSignedIn, isTrue);
        expect(cubit.state.error, contains('does not match'));
        expect(repo.uploads, 0);
      },
    );

    test('an account with no backup still gets its password back', () async {
      await atCodeStage();
      repo.downloadAnswer = APIResponse.success(null);

      await cubit.completeAccountRecovery(
        code: '12345678',
        recoveryKey: goodKey,
        newPassword: newPassword,
      );

      expect(cubit.state.isSignedIn, isTrue);
      expect(cubit.state.error, isNull);
      expect(cubit.state.successMessage, contains('no backup'));
    });
  });

  group('replacing the recovery key', () {
    test('an account holder is checked against the derived password', () async {
      // Regression: the panel used to hand the raw typed password to the
      // vault, whose blob is wrapped under KDF(typed, "vault"). Everyone with
      // an account was told their correct password was wrong.
      final keys = await crypto.deriveAccountKeys(
        email: email,
        password: 'my-password',
      );
      vault.wrappedUnder = keys.vaultPassword;
      cubit.emit(const SupabaseBackupState(isSignedIn: true, email: email));

      final result = await cubit.replaceRecoveryKey(password: 'my-password');

      expect(result.success, isTrue, reason: result.error ?? '');
      // And the new wrap has to reach the stored backup, or the key would only
      // work on this device.
      expect(repo.uploads, 1);
    });

    test('privacy mode is checked against the typed password', () async {
      vault.wrappedUnder = 'my-password';
      cubit.emit(const SupabaseBackupState(isSignedIn: false));

      final result = await cubit.replaceRecoveryKey(password: 'my-password');

      expect(result.success, isTrue, reason: result.error ?? '');
      expect(repo.uploads, 0, reason: 'no account to upload to');
    });

    test('a genuinely wrong password is still refused', () async {
      vault.wrappedUnder = 'my-password';
      cubit.emit(const SupabaseBackupState(isSignedIn: false));

      final result = await cubit.replaceRecoveryKey(password: 'not-it');
      expect(result.success, isFalse);
      expect(result.error, 'Wrong password');
    });
  });

  group('the change-password panel', () {
    testWidgets('goes back to its resting state once the change lands', (
      tester,
    ) async {
      Widget panelAt(SupabaseBackupState state) => MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
              BlocProvider<SupabaseBackupCubit>.value(value: cubit),
            ],
            child: Builder(
              builder: (context) => ChangePasswordPanel(state: state),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        panelAt(const SupabaseBackupState(isSignedIn: true, email: email)),
      );
      await tester.tap(find.text('Change password'));
      await tester.pump();
      expect(find.text('CURRENT PASSWORD'), findsOneWidget);

      // Mid-flow.
      await tester.pumpWidget(
        panelAt(
          const SupabaseBackupState(
            isSignedIn: true,
            email: email,
            passwordChange: PasswordChangeStage.enterCode,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('CODE FROM EMAIL'), findsOneWidget);

      // Done. It used to fall back to asking for the current password again,
      // which read as though nothing had happened.
      await tester.pumpWidget(
        panelAt(
          const SupabaseBackupState(
            isSignedIn: true,
            email: email,
            successMessage: 'Password changed.',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('CURRENT PASSWORD'), findsNothing);
      expect(find.text('Change password'), findsOneWidget);
    });
  });
}
