import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import 'widgets/account_step.dart';
import 'widgets/password_step.dart';
import 'widgets/welcome_step.dart';

/// Full-screen onboarding flow for first-time users.
///
/// Contains a [PageView] with three steps:
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
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                WelcomeStep(
                  onContinueWithAccount: () => _goTo(1),
                  onContinuePrivately: () => _goTo(2),
                ),
                AccountStep(onBack: () => _goTo(0)),
                PasswordStep(onBack: () => _goTo(0)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
