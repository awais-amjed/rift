import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/repositories/supabase_backup_repository.dart';
import '../vault/vault_cubit.dart';

part 'supabase_backup_state.dart';

/// Manages cloud backup via the central Supabase server.
///
/// Handles:
/// - Sign up / sign in / sign out
/// - Uploading the local encrypted backup to Supabase
/// - Downloading a backup from Supabase and importing it into the vault
class SupabaseBackupCubit extends Cubit<SupabaseBackupState> {
  final SupabaseBackupRepository _repo;
  final VaultCubit _vaultCubit;

  SupabaseBackupCubit({
    required VaultCubit vaultCubit,
    SupabaseBackupRepository? repo,
  })  : _repo = repo ?? SupabaseBackupRepository(),
        _vaultCubit = vaultCubit,
        super(const SupabaseBackupState()) {
    // Reflect any persisted Supabase session (e.g. after app restart).
    final user = _repo.currentUser;
    if (user != null) {
      emit(SupabaseBackupState(isSignedIn: true, email: user.email));
    }
  }

  // ── Auth ──────────────────────────────────────────────────

  /// Creates a new account on the central server and immediately signs in.
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    try {
      final user = await _repo.signUp(email: email, password: password);
      emit(state.copyWith(
        isProcessing: false,
        isSignedIn: true,
        email: user.email,
        successMessage: 'Account created! You are now signed in.',
      ));
    } on AuthException catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  /// Signs in to the central server.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    try {
      final user = await _repo.signIn(email: email, password: password);
      emit(state.copyWith(
        isProcessing: false,
        isSignedIn: true,
        email: user.email,
        successMessage: 'Signed in successfully.',
      ));
    } on AuthException catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  /// Signs out of the central server.
  Future<void> signOut() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    try {
      await _repo.signOut();
      emit(SupabaseBackupState(isSignedIn: false));
    } catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  // ── Backup ────────────────────────────────────────────────

  /// Exports the local encrypted backup and uploads it to Supabase.
  Future<void> saveBackupToCloud() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    try {
      final export = await _vaultCubit.exportBackup();
      if (!export.success || export.content == null) {
        emit(state.copyWith(
          isProcessing: false,
          error: export.error ?? 'Failed to export backup',
        ));
        return;
      }

      await _repo.uploadBackup(export.content!);
      emit(state.copyWith(
        isProcessing: false,
        successMessage: 'Backup saved to cloud successfully.',
      ));
    } on AuthException catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  /// Downloads the cloud backup and imports it into the vault.
  ///
  /// [vaultPassword] is the master password used to decrypt the backup.
  Future<void> importBackupFromCloud({required String vaultPassword}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    try {
      final backupJson = await _repo.downloadBackup();
      if (backupJson == null) {
        emit(state.copyWith(
          isProcessing: false,
          error: 'No backup found on server.',
        ));
        return;
      }

      final result = await _vaultCubit.importBackup(
        jsonContent: backupJson,
        password: vaultPassword,
      );

      if (result.success) {
        emit(state.copyWith(
          isProcessing: false,
          successMessage: 'Backup imported successfully.',
        ));
      } else {
        emit(state.copyWith(
          isProcessing: false,
          error: result.error ?? 'Failed to import backup.',
        ));
      }
    } on AuthException catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  void clearMessage() => emit(state.copyWith(clearMessage: true));
}


