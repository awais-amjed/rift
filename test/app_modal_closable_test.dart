import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_modal.dart';
import 'package:rift/presentation/common/back_chevron_button.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
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

/// A join waiting on the server must not be closed: the server already
/// counts the member, and a join left off the list cannot be made again. A
/// [PopScope] held Escape and a click outside, but the X and a page's arrow
/// pop the route themselves, and the X closed the join dialog mid-request
/// (found live Nov 22).
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> open(
    WidgetTester tester, {
    required bool closable,
    Size window = const Size(1600, 900),
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AppModal(
                  title: 'Join',
                  pageOnPhone: true,
                  closable: closable,
                  content: const SizedBox(height: 40, width: 200),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the X closes a closable modal', (tester) async {
    await open(tester, closable: true);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(AppModal), findsNothing);
  });

  testWidgets('the X is held while the modal is not closable', (tester) async {
    await open(tester, closable: false);
    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AppModal), findsOneWidget);
  });

  testWidgets('a page arrow on a phone is held too', (tester) async {
    await open(tester, closable: false, window: const Size(400, 800));
    expect(find.byType(BackChevronButton), findsOneWidget);
    await tester.tap(find.byType(BackChevronButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AppModal), findsOneWidget);
  });
}
