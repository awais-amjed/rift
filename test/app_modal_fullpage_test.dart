import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
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

const _contentKey = Key('modal-content');

/// `fullPage` is layout, and layout is the one thing a compile cannot check.
/// Two pieces of it are quietly fragile: `BoxConstraints.expand()` only fills
/// because `Dialog`'s `Align` hands down loose constraints, and the centred
/// content column only shrink-wraps because it sits in a scroll view. Moving
/// either widget breaks the layout without breaking the build.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  const window = Size(1600, 900);

  Future<void> pump(WidgetTester tester, {required bool fullPage}) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: AppModal(
            title: 'Add Server',
            fullPage: fullPage,
            maxWidth: K.dialogContentWidth,
            content: const SizedBox(
              key: _contentKey,
              height: 40,
              width: double.infinity,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a full-page modal fills the window but for the inset', (
    tester,
  ) async {
    await pump(tester, fullPage: true);

    final size = tester.getSize(_surface);
    expect(size.height, window.height - K.dialogInset * 2);
    expect(size.width, window.width - K.dialogInset * 2);
  });

  testWidgets('the form stays readable while the frame grows', (tester) async {
    await pump(tester, fullPage: true);

    // The header spans the frame — title in the corner, close button in the
    // opposite one — but the form below it does not stretch with it.
    final title = tester.getRect(find.text('Add Server'));
    expect(title.left, lessThan(K.dialogInset + 40));

    final form = tester.getRect(find.byKey(_contentKey));
    expect(form.width, K.dialogContentWidth);
    expect(form.center.dx, window.width / 2);
  });

  testWidgets('a content-sized modal still hugs its content', (tester) async {
    await pump(tester, fullPage: false);

    final size = tester.getSize(_surface);
    expect(size.height, lessThan(200));
    expect(size.width, lessThanOrEqualTo(K.dialogContentWidth));
  });
}
