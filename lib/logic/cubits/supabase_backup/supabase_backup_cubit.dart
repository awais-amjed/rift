import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../data/repositories/supabase_backup_repository.dart';
import '../../../logic/helper_methods.dart';
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
    // Reflect any persisted session restored by supabase_flutter on startup.
    final user = _repo.currentUser;
    if (user != null) {
      emit(SupabaseBackupState(isSignedIn: true, email: user.email));
    }
  }

  // ── Auth ──────────────────────────────────────────────────

  /// Creates a new account on the central server.
  ///
  /// If the server requires email confirmation the state transitions to
  /// [needsEmailConfirmation] so the UI shows a "check your inbox" message.
  Future<void> signUp({required String email, required String password}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    final response = await _repo.signUp(email: email, password: password);
    if (!response.success) {
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }
    final data = response.data as Map<String, dynamic>;
    final needsConfirmation = data['needsConfirmation'] as bool;
    if (needsConfirmation) {
      emit(state.copyWith(
        isProcessing: false,
        needsEmailConfirmation: true,
        email: email,
      ));
    } else {
      final user = data['user'] as User;
      emit(state.copyWith(
        isProcessing: false,
        isSignedIn: true,
        email: user.email,
        successMessage: 'Account created! You are now signed in.',
      ));
    }
  }

  /// Signs in to the central server.
  Future<void> signIn({required String email, required String password}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    final response = await _repo.signIn(email: email, password: password);
    if (!response.success) {
      HelperMethods.printDebug('[SupabaseBackup] signIn failed: ${response.error}');
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }
    final user = response.data as User;
    emit(state.copyWith(
      isProcessing: false,
      isSignedIn: true,
      needsEmailConfirmation: false,
      email: user.email,
      successMessage: 'Signed in successfully.',
    ));
  }

  /// Signs out of the central server.
  Future<void> signOut() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    final response = await _repo.signOut();
    if (!response.success) {
      HelperMethods.printDebug('[SupabaseBackup] signOut failed: ${response.error}');
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }
    emit(const SupabaseBackupState());
  }

  // ── Backup ────────────────────────────────────────────────

  /// Exports the local encrypted backup and uploads it to Supabase.
  Future<void> saveBackupToCloud() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final export = await _vaultCubit.exportBackup();
    if (!export.success || export.content == null) {
      emit(state.copyWith(
        isProcessing: false,
        error: export.error ?? 'Failed to export backup',
      ));
      return;
    }

    final response = await _repo.uploadBackup(export.content!);
    if (!response.success) {
      HelperMethods.printDebug('[SupabaseBackup] uploadBackup failed: ${response.error}');
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }
    emit(state.copyWith(
      isProcessing: false,
      successMessage: 'Backup saved to cloud successfully.',
    ));
  }

  /// Downloads the cloud backup and imports it into the vault.
  Future<void> importBackupFromCloud({required String vaultPassword}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final downloadResponse = await _repo.downloadBackup();
    if (!downloadResponse.success) {
      HelperMethods.printDebug('[SupabaseBackup] downloadBackup failed: ${downloadResponse.error}');
      emit(state.copyWith(isProcessing: false, error: downloadResponse.error));
      return;
    }

    final backupJson = downloadResponse.data as String?;
    if (backupJson == null) {
      emit(state.copyWith(isProcessing: false, error: 'No backup found on server.'));
      return;
    }

    final result = await _vaultCubit.importBackup(
      jsonContent: backupJson,
      password: vaultPassword,
    );
    if (result.success) {
      emit(state.copyWith(isProcessing: false, successMessage: 'Backup imported successfully.'));
    } else {
      emit(state.copyWith(isProcessing: false, error: result.error ?? 'Failed to import backup.'));
    }
  }

  void clearMessage() => emit(state.copyWith(clearMessage: true));
}
