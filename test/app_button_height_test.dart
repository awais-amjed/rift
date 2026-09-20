import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_button.dart';
import 'package:rift/presentation/common/app_button_height.dart';
import 'package:rift/presentation/theme/app_theme.dart';
import 'package:rift/presentation/theme/palettes/indigo_palette.dart';

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

/// A button must be the height it was handed.
///
/// Not a style question: [AppButton] pins `minimumSize` and `maximumSize`,
/// and Material then applies the theme's **visual density** to those
/// constraints and to nothing else nearby. On a desktop the adaptive default
/// is `compact` — −1 vertical, −4px — so every button came out four pixels
/// shorter than the plain containers it lines up with, and the one place it
/// showed was a `QuietDangerButton` stacked under a primary. `tapTargetSize:
/// shrinkWrap` does not cover it; density is a separate subtraction.
///
/// So these render under the density a desktop actually resolves to, and
/// measure the box rather than reasoning about it.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HydratedBloc.storage = _MemoryStorage();
  });

  Future<void> host(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          // The density a desktop resolves to, stated rather than inherited
          // from the test's platform — which is Android, where the adaptive
          // default is standard and the bug could not appear at all.
          theme: AppTheme.fromPalette(
            indigoPalette,
            Brightness.dark,
          ).copyWith(visualDensity: VisualDensity.compact),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  group('a button is as tall as it was told to be', () {
    testWidgets('the default is a control height, not four less', (
      tester,
    ) async {
      await host(tester, const AppButton(label: 'Message'));
      expect(tester.getSize(find.byType(AppButton)).height, K.controlHeight);
    });

    testWidgets("a phone footer's thumb target is the full height", (
      tester,
    ) async {
      await host(
        tester,
        const AppButtonHeight(
          height: K.thumbCtaHeight,
          child: AppButton(label: 'Add server'),
        ),
      );
      expect(tester.getSize(find.byType(AppButton)).height, K.thumbCtaHeight);
    });

    testWidgets('an explicit height is honoured exactly', (tester) async {
      await host(tester, const AppButton(label: 'Copy', height: 38));
      expect(tester.getSize(find.byType(AppButton)).height, 38);
    });
  });
}
