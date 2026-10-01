import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/network/network_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/popover_surface.dart';
import 'package:rift/presentation/common/title_bar/app_title_bar.dart';

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

/// The style the framework falls back to when a [Text] has no [Material] above
/// it — red monospace struck with a double yellow underline. Anything Rift
/// mounts into the root [Overlay] sits beside the [Navigator] rather than
/// inside a [Scaffold], so it gets this unless it carries its own Material.
const _errorDecorationColor = Color(0xFFFFFF00);

/// Resolves what a [Text] will actually paint with, after the inherited
/// [DefaultTextStyle] has been merged in — which is where the fallback hides.
TextStyle _paintedStyle(WidgetTester tester, String text) {
  final richText = tester.widget<RichText>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  return (richText.text as TextSpan).style!;
}

void _expectNoFallback(TextStyle style) {
  expect(style.decoration, isNot(TextDecoration.underline));
  expect(style.decorationStyle, isNot(TextDecorationStyle.double));
  expect(style.decorationColor, isNot(_errorDecorationColor));
}

Future<void> _pumpBesideNavigator(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    // Deliberately no Scaffold: this reproduces the overlay's own context,
    // where the only DefaultTextStyle in scope is MaterialApp's fallback.
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          // Offline, so the title bar's "No internet" chip is drawn too.
          BlocProvider(
            create: (_) => NetworkCubit(
              changes: const Stream.empty(),
              check: () async => const [ConnectivityResult.none],
              settle: Duration.zero,
            ),
          ),
        ],
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
  await tester.pump();
  // The connectivity answer lands, settles (zero here) and redraws the bar.
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  setUpAll(() {
    // The title bar asks the platform whether the window is maximized as soon
    // as it mounts; without a handler that throws asynchronously mid-test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
  });

  group('text mounted beside the Navigator', () {
    testWidgets('falls back to the error style with no Material — the bug', (
      tester,
    ) async {
      // Guards the guard: if this ever stops reproducing, the assertions in
      // the tests below would pass for the wrong reason.
      await _pumpBesideNavigator(tester, const Text('unprotected'));

      final style = _paintedStyle(tester, 'unprotected');
      expect(style.decoration, TextDecoration.underline);
      expect(style.decorationStyle, TextDecorationStyle.double);
      expect(style.decorationColor, _errorDecorationColor);
    });

    testWidgets('the title bar wordmark carries its own Material', (
      tester,
    ) async {
      await _pumpBesideNavigator(
        tester,
        const SizedBox(width: 800, child: AppTitleBar()),
      );

      _expectNoFallback(_paintedStyle(tester, 'rift'));
      _expectNoFallback(_paintedStyle(tester, 'No internet'));
    });

    testWidgets('PopoverSurface carries one for every popover', (tester) async {
      await _pumpBesideNavigator(
        tester,
        const PopoverSurface(child: Text('menu heading')),
      );

      _expectNoFallback(_paintedStyle(tester, 'menu heading'));
    });
  });
}
