import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_button.dart';
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
/// bigger than that. Three things need holding: it must not stretch to the
/// window, it must not scroll while the window has room for it — which a fixed
/// pixel cap got wrong for the create-server form — and it must stop somewhere
/// short of the window on content that has no natural end.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  const maxWidth = 480.0;

  Future<void> pump(
    WidgetTester tester, {
    required double contentHeight,
    Size window = const Size(1600, 900),
    List<Widget>? actions,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: AppModal(
            title: 'Add server',
            maxWidth: maxWidth,
            content: SizedBox(height: contentHeight, width: double.infinity),
            actions: actions,
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

  testWidgets('a tall form does not scroll while the window has room', (
    tester,
  ) async {
    // Roughly the create-server form: six fields, two section headers and a
    // button row. It used to scroll here against a 560px cap.
    await pump(tester, contentHeight: 560);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;

    expect(scroll, isNotNull);
    expect(position.maxScrollExtent, 0, reason: 'nothing to scroll to');
  });

  testWidgets('it still stops short of filling the window', (tester) async {
    await pump(tester, contentHeight: 2000);

    final height = tester.getSize(_surface).height;
    expect(height, lessThan(900 * 0.9));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position,
      isA<ScrollPosition>().having(
        (p) => p.maxScrollExtent,
        'maxScrollExtent',
        greaterThan(0),
      ),
    );
  });

  testWidgets('a small window makes it scroll rather than overflow', (
    tester,
  ) async {
    await pump(tester, contentHeight: 560, window: const Size(1000, 600));

    expect(tester.getSize(_surface).height, lessThanOrEqualTo(600 * 0.85));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position,
      isA<ScrollPosition>().having(
        (p) => p.maxScrollExtent,
        'maxScrollExtent',
        greaterThan(0),
      ),
    );
  });

  testWidgets('footer buttons keep their own width and sit at the end', (
    tester,
  ) async {
    await pump(
      tester,
      contentHeight: 120,
      actions: const [
        AppButton(label: 'Cancel', variant: AppButtonVariant.secondary),
        AppButton(label: 'Save'),
      ],
    );

    final dialog = tester.getRect(_surface);
    final cancel = tester.getRect(find.widgetWithText(AppButton, 'Cancel'));
    final save = tester.getRect(find.widgetWithText(AppButton, 'Save'));

    // Each is the width of its own label. Dividing the footer between them
    // made Cancel as wide as the thing it cancels.
    expect(save.width, lessThan(maxWidth / 3));
    expect(cancel.width, lessThan(maxWidth / 3));

    // Gathered at the trailing edge, in order, against the footer's padding.
    expect(cancel.right, lessThan(save.left));
    expect(dialog.right - save.right, moreOrLessEquals(20, epsilon: 0.5));
  });
}
