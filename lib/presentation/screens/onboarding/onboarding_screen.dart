import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import 'widgets/account_step.dart';
import 'widgets/password_step.dart';
import 'widgets/welcome_step.dart';

/// Full-screen onboarding flow for first-time users.
///
/// Three steps, cross-faded (no PageView — sliding from welcome to privacy
/// mode must not flash the account page in between):
/// 1. Welcome — explains the system; choose account (default) or privacy mode.
/// 2. Account — central-server sign in/up; backup restore/create is automatic.
/// 3. Privacy — create a local-only vault (or restore from a backup file);
///    no central-server contact.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _page = 0;

  void _goTo(int page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    final page = switch (_page) {
      1 => AccountStep(onBack: () => _goTo(0)),
      2 => PasswordStep(onBack: () => _goTo(0)),
      _ => WelcomeStep(
          onContinueWithAccount: () => _goTo(1),
          onContinuePrivately: () => _goTo(2),
        ),
    };

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(_page), child: page),
            ),
          ),
        ),
      ),
    );
  }
}
