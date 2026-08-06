import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/settings/widgets/settings_sidebar.dart';
import 'package:rift/presentation/screens/settings/widgets/settings_tab.dart';

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

/// Records what the sidebar's callbacks fired, so a stray tap is visible.
class _Taps {
  int back = 0;
  int reset = 0;
  SettingsTab? tab;
}

Future<_Taps> _pumpSidebar(WidgetTester tester) async {
  final taps = _Taps();
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider(
        create: (_) => ThemeCubit(),
        child: Scaffold(
          body: SizedBox(
            width: 264,
            height: 700,
            child: SettingsSidebar(
              activeTab: SettingsTab.appearance,
              onTabSelected: (tab) => taps.tab = tab,
              themeState: ThemeState(),
              onBack: () => taps.back++,
              onResetVault: () => taps.reset++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return taps;
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('the settings nav header', () {
    testWidgets('does not navigate when the heading is tapped', (tester) async {
      final taps = await _pumpSidebar(tester);

      await tester.tap(find.text('Settings'));
      await tester.pump();

      // The heading names the panel you are already in.
      expect(taps.back, 0);
    });

    testWidgets('does not navigate when the subtitle is tapped', (
      tester,
    ) async {
      final taps = await _pumpSidebar(tester);

      // Reads like a description of the arrow, not a second copy of it.
      await tester.tap(find.text('Back to home'));
      await tester.pump();

      expect(taps.back, 0);
    });

    testWidgets('goes back from the arrow', (tester) async {
      final taps = await _pumpSidebar(tester);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();

      expect(taps.back, 1);
      // Leaving settings is not also a tab change.
      expect(taps.tab, isNull);
    });
  });

  testWidgets('the tabs still switch', (tester) async {
    final taps = await _pumpSidebar(tester);

    await tester.tap(find.text('Cloud Backup'));
    await tester.pump();

    expect(taps.tab, SettingsTab.backup);
    expect(taps.back, 0);
  });
}
