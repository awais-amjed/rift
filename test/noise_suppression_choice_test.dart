import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/enums/noise_filter_work.dart';
import 'package:rift/data/enums/noise_suppression.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/settings/widgets/voice_audio/noise_suppression_choice.dart';

import 'helpers/memory_storage.dart';

Future<void> _pump(WidgetTester tester, NoiseFilterWork work) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: NoiseSuppressionChoice(
            value: NoiseSuppression.standard,
            work: work,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

/// On Windows the noise models turn up a moment after Dart starts, and
/// DPDFNet takes a moment to load the first time. A choice that seems to do
/// nothing meanwhile gets picked again, so the line under it says so.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('says what a choice is waiting on, then what it suits', (
    tester,
  ) async {
    await _pump(tester, NoiseFilterWork.starting);
    expect(find.text('Starting noise suppression…'), findsOneWidget);
    expect(find.text('Best for a quiet room.'), findsNothing);

    await _pump(tester, NoiseFilterWork.loadingModel);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading DPDFNet…'), findsOneWidget);

    await _pump(tester, NoiseFilterWork.none);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Loading DPDFNet…'), findsNothing);
    expect(find.text('Best for a quiet room.'), findsOneWidget);
  });

  test('only the end of the wait for the runner sets the call up again', () {
    expect(NoiseFilterWork.starting.startedSince(NoiseFilterWork.none), true);
    expect(
      NoiseFilterWork.starting.startedSince(NoiseFilterWork.loadingModel),
      true,
    );
    expect(
      NoiseFilterWork.starting.startedSince(NoiseFilterWork.starting),
      false,
    );
    expect(
      NoiseFilterWork.loadingModel.startedSince(NoiseFilterWork.none),
      false,
    );
  });
}
