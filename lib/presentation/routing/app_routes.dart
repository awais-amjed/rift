import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/enums/auth_status.dart';
import '../../logic/cubits/vault/vault_cubit.dart';
import '../screens/home/backups/supabase/supabase_backup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/recovery_key/recovery_key_screen.dart';
import '../screens/settings/settings_screen.dart';

class AppRoutes {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext get context => navigatorKey.currentContext!;

  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String recoveryKey = '/recovery-key';
  static const String supabaseBackup = '/backup/cloud';
  static const String settings = '/settings';

  static GoRouter router(VaultCubit vaultCubit) => GoRouter(
    initialLocation: home,
    navigatorKey: navigatorKey,
    refreshListenable: _VaultRefreshListenable(vaultCubit),
    redirect: (context, state) {
      final vaultState = vaultCubit.state;
      final isOnboarding = state.matchedLocation == onboarding;
      final isRecoveryKey = state.matchedLocation == recoveryKey;

      // Still checking — don't redirect yet.
      if (vaultState.status == AuthStatus.unknown) return null;

      // Fresh user → must onboard.
      if (vaultState.status == AuthStatus.fresh) {
        return isOnboarding ? null : onboarding;
      }

      // Unlocked → but a recovery key that was generated and never
      // acknowledged outranks everywhere else. It exists only in memory and in
      // one temporary storage key until it is written down, so letting anyone
      // reach the app around it is how it gets lost. See [RecoveryKeyScreen].
      if (vaultState.status == AuthStatus.unlocked) {
        if (vaultState.pendingRecoveryKey != null) {
          return isRecoveryKey ? null : recoveryKey;
        }
        return (isOnboarding || isRecoveryKey) ? home : null;
      }

      return null;
    },
    routes: [
      GoRoute(path: home, builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: recoveryKey,
        builder: (context, state) => const RecoveryKeyScreen(),
      ),
      GoRoute(
        path: supabaseBackup,
        builder: (context, state) => const SupabaseBackupScreen(),
      ),
      GoRoute(
        path: settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

/// Converts [VaultCubit] stream into a [Listenable] for [GoRouter.refreshListenable].
class _VaultRefreshListenable extends ChangeNotifier {
  _VaultRefreshListenable(VaultCubit cubit) {
    cubit.stream.listen((_) => notifyListeners());
  }
}
