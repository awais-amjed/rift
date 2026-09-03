import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/repositories/supabase_backup_repository.dart';
import 'package:rift/logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/presentation/screens/onboarding/widgets/account_step/auth_view.dart';

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

class _OfflineRepo implements SupabaseBackupRepository {
  @override
  User? get currentUser => null;

  @override
  bool get isSignedIn => false;

  @override
  Stream<AuthState> get authChanges => const Stream.empty();

  @override
  Future<APIResponse> resendConfirmation({required String email}) async =>
      APIResponse.success(null);

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not part of this test');
}

/// Onboarding opens on **sign in**, not on sign up.
///
/// It is reached whenever there is no local vault, which is as often a
/// reinstall or a second device as it is a new account — and for that group,
/// creating a second account is the one thing they must not do, because the
/// vault they came for is behind the first one. Someone genuinely new loses two
/// seconds and a click; someone who signs up twice loses their servers.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider(
            create: (_) => SupabaseBackupCubit(
              vaultCubit: VaultCubit(),
              repo: _OfflineRepo(),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AuthView(
              state: const SupabaseBackupState(),
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the form opens on sign in', (tester) async {
    await pump(tester);

    expect(find.text('Sign In to Rift'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Create Your Account'), findsNothing);
    // The surest tell, because it exists only on the sign-up form.
    // Upper-cased: that is how `AppTextField` draws a label.
    expect(find.text('CONFIRM PASSWORD'), findsNothing);
  });

  testWidgets('and offers the other way without hiding it', (tester) async {
    await pump(tester);
    expect(find.text('New here? Create an account'), findsOneWidget);
  });

  testWidgets('which switches to sign up when taken', (tester) async {
    await pump(tester);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();

    expect(find.text('Create Your Account'), findsOneWidget);
    expect(find.text('CONFIRM PASSWORD'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
  });

  testWidgets('a greeting nobody has earned yet is not shown', (tester) async {
    // "Welcome Back" is right for a returning account and wrong as the first
    // thing a brand-new one reads — which is what it became the moment sign in
    // stopped being the second screen.
    await pump(tester);
    expect(find.textContaining('Welcome Back'), findsNothing);
  });
}
