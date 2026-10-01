import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/central_dm/central_dm_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/dms/central_dm_view.dart';

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

class _StubCentralDmCubit extends Cubit<CentralDmState>
    implements CentralDmCubit {
  _StubCentralDmCubit(CentralDmStatus status)
    : super(CentralDmState(status: status));

  int retries = 0;

  @override
  Future<void> retryReady() async => retries++;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Central unreachable when Rift DMs get ready.
///
/// This state used to read "Finding your account…" and stay that way with no
/// way out but a restart. It now says what is wrong and offers to ask again —
/// the cubit also asks again by itself.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<_StubCentralDmCubit> pump(
    WidgetTester tester,
    CentralDmStatus status,
  ) async {
    final cubit = _StubCentralDmCubit(status);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<CentralDmCubit>.value(value: cubit),
        ],
        child: const MaterialApp(home: Scaffold(body: CentralDmView())),
      ),
    );
    return cubit;
  }

  testWidgets('a pass that could not reach central says so, with Try again', (
    tester,
  ) async {
    final cubit = await pump(tester, CentralDmStatus.error);
    expect(find.text("Can't reach your Rift account"), findsOneWidget);
    expect(find.text('Finding your account…'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(cubit.retries, 1);
  });

  testWidgets('signed out offers no retry: there is nothing to reach', (
    tester,
  ) async {
    await pump(tester, CentralDmStatus.signedOut);
    expect(find.text('Rift DMs need an account'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
