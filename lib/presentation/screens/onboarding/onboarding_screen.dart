import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import 'widgets/import_backup_step.dart';
import 'widgets/password_step.dart';
import 'widgets/welcome_step.dart';

/// Full-screen onboarding flow for first-time users.
///
/// Contains a [PageView] with three steps:
/// 1. Welcome — explains the system and invites the user to continue.
/// 2. Password — collects a master password and creates the vault.
/// 3. Import Backup — sign in to cloud backup and restore a vault.
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

  void _goToPassword() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _goToWelcome() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _goToImportBackup() {
    _pageController.animateToPage(
      2,
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
                WelcomeStep(onContinue: _goToPassword, onRestore: _goToImportBackup),
                PasswordStep(onBack: _goToWelcome),
                ImportBackupStep(onBack: _goToWelcome),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
