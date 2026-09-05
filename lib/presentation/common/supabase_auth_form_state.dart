import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';

/// The email/password half of every "sign in to cloud backup" surface —
/// controllers, the sign-in/sign-up mode, and the cubit call.
///
/// Only the logic is shared: onboarding wants a full page with a confirm
/// field and a strength meter, the settings panel wants a dense row, and the
/// backup dialog sits in between. Mix this into their `State` and lay the
/// fields out however that surface needs.
mixin SupabaseAuthFormState<T extends StatefulWidget> on State<T> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isSignUp = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// Submit whatever is in the fields. Callers that validate first (onboarding)
  /// should do so before calling this.
  void submitCredentials() {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final cubit = context.read<SupabaseBackupCubit>();
    if (isSignUp) {
      cubit.signUp(email: email, password: password);
    } else {
      cubit.signIn(email: email, password: password);
    }
  }
}
