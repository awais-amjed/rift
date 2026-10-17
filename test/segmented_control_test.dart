import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/segmented_control.dart';

import 'helpers/memory_storage.dart';

const _filters = [
  SegmentOption(value: 0, label: 'Off'),
  SegmentOption(value: 1, label: 'Standard'),
  SegmentOption(value: 2, label: 'RNNoise'),
  SegmentOption(value: 3, label: 'DeepFilterNet'),
  SegmentOption(value: 4, label: 'DPDFNet'),
];

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: Center(
            child: SizedBox(
              width: width,
              child: SegmentedControl<int>(
                options: _filters,
                value: 2,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _anyLabelCut(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(find.byType(Text))
    .any((p) => p.didExceedMaxLines);

/// Five noise filters on a phone came out as "Standa…", "RNNoi…", "DeepFi…":
/// equal segments in one row, each too narrow for its name.
///
/// The test font draws every letter a square em wide, so "DeepFilterNet"
/// needs about 200 of these widths, not the 100 it takes in Geist.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('labels that fit stay on one row', (tester) async {
    await _pump(tester, 1100);
    expect(
      tester.getSize(find.byType(SegmentedControl<int>)).height,
      K.fieldHeight,
    );
    expect(_anyLabelCut(tester), isFalse);
  });

  testWidgets('labels that do not fit go onto even rows, uncut', (
    tester,
  ) async {
    await _pump(tester, 640);
    expect(
      tester.getSize(find.byType(SegmentedControl<int>)).height,
      greaterThan(K.fieldHeight),
    );
    expect(_anyLabelCut(tester), isFalse);

    // Three and two, in the same columns.
    final off = tester.getRect(find.text('Off'));
    final deep = tester.getRect(find.text('DeepFilterNet'));
    final rnnoise = tester.getRect(find.text('RNNoise'));
    expect(deep.top, greaterThan(off.bottom));
    expect(rnnoise.top, off.top);
    final segments = find
        .byType(SizedBox)
        .evaluate()
        .where((e) => (e.widget as SizedBox).height == K.fieldHeight);
    final widths = {
      for (final e in segments) (e.renderObject as RenderBox).size.width,
    };
    expect(widths, hasLength(1));
  });
}
