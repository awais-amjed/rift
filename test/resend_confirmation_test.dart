import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/repositories/supabase_backup_repository.dart';
import 'package:rift/logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/presentation/common/app_button.dart';
import 'package:rift/presentation/common/resend_confirmation_button.dart';
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

/// A repository that answers without a network, so the cubit's own rules can
/// be exercised.
class _FakeRepo implements SupabaseBackupRepository {
  APIResponse answer = APIResponse.success(null);
  final asked = <String>[];

  @override
  Future<APIResponse> resendConfirmation({required String email}) async {
    asked.add(email);
    return answer;
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

/// A confirmation link that never arrives is the most ordinary way to be locked
/// out of an account you just made, and until now the app had no answer to it:
/// the notice said "check your email" and offered one button, which was to go
/// and sign in with an address the server would refuse.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  group('the cubit', () {
    late _FakeRepo repo;
    late SupabaseBackupCubit cubit;

    setUp(() {
      repo = _FakeRepo();
      cubit = SupabaseBackupCubit(vaultCubit: VaultCubit(), repo: repo);
    });

    tearDown(() => cubit.close());

    /// The state the notice is drawn from, as sign-up or a refused sign-in
    /// leaves it.
    void awaitingConfirmation() => cubit.emit(
      const SupabaseBackupState(
        needsEmailConfirmation: true,
        email: 'someone@example.com',
      ),
    );

    test('asks for the address it was signed up with', () async {
      awaitingConfirmation();
      await cubit.resendConfirmation();
      expect(repo.asked, ['someone@example.com']);
    });

    test('says nothing about whether the address exists', () async {
      awaitingConfirmation();
      await cubit.resendConfirmation();
      // The server does not tell us, and it should not: an answer either way
      // would turn this screen into a way of asking which emails hold
      // accounts. So the message is conditional, and deliberately so.
      expect(cubit.state.successMessage, contains('If someone@example.com'));
      expect(cubit.state.error, isNull);
    });

    test('with no address to send to, it does nothing at all', () async {
      cubit.emit(const SupabaseBackupState(needsEmailConfirmation: true));
      await cubit.resendConfirmation();
      expect(repo.asked, isEmpty);
    });

    test('a second ask inside the cooldown never reaches the server', () async {
      awaitingConfirmation();
      await cubit.resendConfirmation();
      await cubit.resendConfirmation();
      await cubit.resendConfirmation();
      expect(repo.asked, hasLength(1));
    });

    test('the cooldown is the gap the central project actually enforces', () {
      // `smtp_max_frequency` on the central project. Asking again sooner is
      // refused, and a refusal spends the same hourly allowance as a send.
      expect(SupabaseBackupCubit.resendCooldown, const Duration(seconds: 60));
    });

    test('a rate limit is reported in the server own words', () async {
      // GoTrue names the wait — "you can only request this after 47 seconds" —
      // and no wording of ours would be more useful than the number.
      repo.answer = APIResponse(
        success: false,
        error:
            'For security purposes, you can only request this after 47 '
            'seconds.',
        errorCode: ErrorCode.emailSendRateLimited,
      );
      awaitingConfirmation();
      await cubit.resendConfirmation();

      expect(cubit.state.error, contains('47 seconds'));
      expect(cubit.state.successMessage, isNull);
    });

    test(
      'any other failure is reworded, because GoTrue writes for logs',
      () async {
        repo.answer = APIResponse(
          success: false,
          error: 'Database error finding user',
          errorCode: 'unexpected_failure',
        );
        awaitingConfirmation();
        await cubit.resendConfirmation();

        expect(cubit.state.error, isNot(contains('Database')));
        expect(cubit.state.error, contains('Try again'));
      },
    );

    test('and a failure still starts the cooldown', () async {
      // Being refused costs an email from the hourly allowance just as being
      // obeyed does, so the button has to lock either way.
      repo.answer = APIResponse(
        success: false,
        error: 'nope',
        errorCode: ErrorCode.emailSendRateLimited,
      );
      awaitingConfirmation();
      await cubit.resendConfirmation();
      expect(cubit.state.resendAvailableAt, isNotNull);

      repo.answer = APIResponse.success(null);
      await cubit.resendConfirmation();
      expect(repo.asked, hasLength(1), reason: 'still inside the cooldown');
    });
  });

  group('the button', () {
    // A clock the test moves, so the countdown can be checked at all: the
    // widget ticks on a Timer, and `pump` advances the framework's clock
    // without touching the wall clock the widget reads.
    late DateTime now;

    Future<void> pump(WidgetTester tester, DateTime? availableAt) =>
        tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => ThemeCubit()),
              BlocProvider(
                create: (_) => SupabaseBackupCubit(
                  vaultCubit: VaultCubit(),
                  repo: _FakeRepo(),
                ),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ResendConfirmationButton(
                  availableAt: availableAt,
                  clock: () => now,
                ),
              ),
            ),
          ),
        );

    setUp(() => now = DateTime(2026, 9, 4, 12));

    bool enabled(WidgetTester tester) =>
        tester.widget<AppButton>(find.byType(AppButton)).onPressed != null;

    testWidgets('offers to send again when nothing is pending', (tester) async {
      await pump(tester, null);
      expect(find.text('Resend'), findsOneWidget);
      expect(enabled(tester), isTrue);
    });

    testWidgets('counts down instead, while the wait is on', (tester) async {
      await pump(tester, now.add(const Duration(seconds: 30)));
      // Disabled and saying why: every click would cost the project an email,
      // so the button cannot be pressed until the wait is over.
      expect(enabled(tester), isFalse);
      expect(find.textContaining('Resend in'), findsOneWidget);
    });

    testWidgets('and the number goes down', (tester) async {
      await pump(tester, now.add(const Duration(seconds: 30)));
      expect(find.textContaining('30s'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('29s'), findsOneWidget);
    });

    testWidgets('and turns back into the offer when it reaches zero', (
      tester,
    ) async {
      await pump(tester, now.add(const Duration(seconds: 2)));
      expect(enabled(tester), isFalse);

      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Resend'), findsOneWidget);
      expect(enabled(tester), isTrue);
    });

    testWidgets('a wait already past reads as ready', (tester) async {
      await pump(tester, now.subtract(const Duration(minutes: 5)));
      expect(find.text('Resend'), findsOneWidget);
      expect(enabled(tester), isTrue);
    });
  });
}
