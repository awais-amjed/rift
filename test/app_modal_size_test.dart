import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_modal.dart';

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

/// The dialog's own surface — the outermost [Material] it paints, not the ones
/// the close button and its ink well add underneath.
final _surface = find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

/// A modal is sized by what is in it, and the window it opens over is much
/// bigger than that. Both halves of that need holding: it must not stretch to
/// the window, and it must not grow past [AppModal.maxHeight] when the content
/// is long — a form that opens window-tall is a lot of dialog for a form.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  const window = Size(1600, 900);
  const maxWidth = 480.0;
  const maxHeight = 560.0;

  Future<void> pump(
    WidgetTester tester, {
    required double contentHeight,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: AppModal(
            title: 'Add Server',
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            content: SizedBox(height: contentHeight, width: double.infinity),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a short modal is only as tall as what is in it', (tester) async {
    await pump(tester, contentHeight: 120);

    final size = tester.getSize(_surface);
    expect(size.width, maxWidth);
    // Content, its padding and the header — nowhere near the window.
    expect(size.height, lessThan(260));
  });

  testWidgets('a long one stops growing and scrolls instead', (tester) async {
    await pump(tester, contentHeight: 2000);

    expect(tester.getSize(_surface).height, maxHeight);
    expect(find.byType(Scrollable), findsOneWidget);
  });
}
