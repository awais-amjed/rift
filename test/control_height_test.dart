import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_text_field.dart';
import 'package:rift/presentation/common/segmented_control.dart';

import 'helpers/memory_storage.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  VisualDensity? density,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(visualDensity: density),
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: Center(child: SizedBox(width: 360, child: child)),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A form's field, its segmented options and the button under them are one
/// height. These widgets used to reach it by padding around their text, which
/// is how they drifted 2–4px apart from the token they were meant to share.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('a single-line field stands at the field height', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(tester, AppTextField(controller: controller, hint: 'Name'));

    expect(tester.getSize(find.byType(TextField)).height, K.fieldHeight);
  });

  // The outline Material paints, not the slot the field takes: the two came
  // apart once, and a test of the slot passed while every form showed a 34px
  // box beside a 44px button.
  Size outline(WidgetTester tester) => tester.getSize(
    find
        .descendant(
          of: find.byType(InputDecorator),
          matching: find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.foregroundPainter.runtimeType.toString() ==
                    '_InputBorderPainter',
          ),
        )
        .first,
  );

  testWidgets('its outline is the field height too', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(tester, AppTextField(controller: controller, hint: 'Name'));

    expect(outline(tester).height, K.fieldHeight);
  });

  testWidgets('and stays it at a desktop\'s compact density', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      AppTextField(controller: controller, hint: 'Name'),
      density: VisualDensity.compact,
    );

    expect(outline(tester).height, K.fieldHeight);
  });

  testWidgets('a counter goes under the outline, not into it', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      AppTextField(controller: controller, hint: 'GitHub', maxLength: 80),
      density: VisualDensity.compact,
    );

    expect(outline(tester).height, K.fieldHeight);
  });

  testWidgets('a prose field still grows past it', (tester) async {
    final controller = TextEditingController(text: 'one\ntwo\nthree\nfour');
    addTearDown(controller.dispose);
    await _pump(tester, AppTextField(controller: controller, maxLines: 4));

    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThan(K.fieldHeight),
    );
  });

  testWidgets('a segmented option stands at the field height', (tester) async {
    await _pump(
      tester,
      SegmentedControl<int>(
        options: const [
          SegmentOption(value: 0, label: 'Text', icon: Icons.tag),
          SegmentOption(value: 1, label: 'Voice'),
        ],
        value: 0,
        onChanged: (_) {},
      ),
    );

    expect(
      tester.getSize(find.byType(SegmentedControl<int>)).height,
      K.fieldHeight,
    );
  });

  testWidgets('a secret field can be shown, and is no taller for it', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'correct-horse');
    addTearDown(controller.dispose);
    await _pump(
      tester,
      AppTextField(controller: controller, obscureText: true),
    );

    EditableText editable() =>
        tester.widget<EditableText>(find.byType(EditableText));
    expect(editable().obscureText, isTrue);
    expect(tester.getSize(find.byType(TextField)).height, K.fieldHeight);

    await tester.tap(find.byTooltip('Show'));
    await tester.pump();
    expect(editable().obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide'));
    await tester.pump();
    expect(editable().obscureText, isTrue);
  });
}
