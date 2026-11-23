import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/enums/noise_filter_work.dart';
import 'package:rift/data/enums/noise_suppression.dart';
import 'package:rift/data/repositories/model_repository.dart';
import 'package:rift/logic/cubits/models/models_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/settings/widgets/voice_audio/noise_suppression_choice.dart';

import 'helpers/memory_storage.dart';

Future<void> _pump(
  WidgetTester tester,
  NoiseFilterWork work, {
  NoiseSuppression value = NoiseSuppression.dpdfnet,
  NoiseSuppression inEffect = NoiseSuppression.dpdfnet,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit()),
            BlocProvider(
              create: (_) => ModelsCubit(models: ModelRepository(source: '')),
            ),
          ],
          child: NoiseSuppressionChoice(
            value: value,
            work: work,
            inEffect: inEffect,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

/// On Windows the noise models turn up a moment after Dart starts, a model
/// downloads the first time it is picked, and DPDFNet takes a moment to load.
/// A choice that seems to do nothing meanwhile gets picked again, so the line
/// under it says so, and what the microphone gets until then.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('says what a choice is waiting on, then what it suits', (
    tester,
  ) async {
    await _pump(
      tester,
      NoiseFilterWork.starting,
      value: NoiseSuppression.standard,
      inEffect: NoiseSuppression.standard,
    );
    expect(find.text('Starting noise suppression…'), findsOneWidget);
    expect(find.text('Best for a quiet room.'), findsNothing);

    await _pump(tester, NoiseFilterWork.loadingModel);
    expect(find.text('Loading DPDFNet…'), findsOneWidget);

    await _pump(tester, NoiseFilterWork.none);
    expect(find.text('Loading DPDFNet…'), findsNothing);
    // No runner in a test, so DPDFNet is not offered and shows as Standard.
    expect(find.text('Best for a quiet room.'), findsOneWidget);
  });

  testWidgets('says what stands in while a model downloads', (tester) async {
    await _pump(
      tester,
      NoiseFilterWork.downloadingModel,
      inEffect: NoiseSuppression.standard,
    );
    expect(find.text('Downloading DPDFNet 0% · Standard for now'), findsOne);

    await _pump(
      tester,
      NoiseFilterWork.modelUnavailable,
      inEffect: NoiseSuppression.rnnoise,
    );
    expect(find.text("DPDFNet didn't download · RNNoise for now"), findsOne);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('says when DPDFNet cannot run here, and what stands in', (
    tester,
  ) async {
    await _pump(
      tester,
      NoiseFilterWork.modelCannotRun,
      inEffect: NoiseSuppression.rnnoise,
    );
    expect(
      find.text("DPDFNet can't run on this computer · RNNoise instead"),
      findsOne,
    );
    expect(find.text('Try again'), findsNothing);
  });
}
