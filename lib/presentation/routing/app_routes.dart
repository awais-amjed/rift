import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/enums/auth_status.dart';
import '../../logic/cubits/vault/vault_cubit.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/backups/supabase/supabase_backup_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';

class AppRoutes {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext get context => navigatorKey.currentContext!;

  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String supabaseBackup = '/backup/cloud';

  static GoRouter router(VaultCubit vaultCubit) => GoRouter(
        initialLocation: home,
        navigatorKey: navigatorKey,
        refreshListenable: _VaultRefreshListenable(vaultCubit),
        redirect: (context, state) {
          final vaultState = vaultCubit.state;
          final isOnboarding = state.matchedLocation == onboarding;

          // Still checking — don't redirect yet.
          if (vaultState.status == AuthStatus.unknown) return null;

          // Fresh user → must onboard.
          if (vaultState.status == AuthStatus.fresh) {
            return isOnboarding ? null : onboarding;
          }

          // Unlocked → go home if still on onboarding.
          if (vaultState.status == AuthStatus.unlocked) {
            return isOnboarding ? home : null;
          }

          return null;
        },
        routes: [
          GoRoute(
            path: home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: onboarding,
            builder: (context, state) => const OnboardingScreen(),
          ),
          GoRoute(
            path: supabaseBackup,
            builder: (context, state) => const SupabaseBackupScreen(),
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
