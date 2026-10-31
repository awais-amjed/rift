import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/noise_filter_priority.dart';
import 'package:rift/data/enums/noise_suppression.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

void main() {
  AppState saved(Object? value) => AppState.fromJson(
    const AppState().toJson()..['noiseSuppression'] = value,
  );

  test('a new install starts on DPDFNet', () {
    expect(const AppState().noiseSuppression, NoiseSuppression.dpdfnet);
  });

  test('each choice survives a JSON round-trip', () {
    for (final mode in NoiseSuppression.values) {
      final state = AppState(noiseSuppression: mode);
      expect(AppState.fromJson(state.toJson()).noiseSuppression, mode);
    }
  });

  test('the old switch, saved as a bool, keeps off off', () {
    expect(saved(false).noiseSuppression, NoiseSuppression.off);
    expect(saved(true).noiseSuppression, NoiseSuppression.dpdfnet);
  });

  test('DeepFilterNet, no longer offered, reads as DPDFNet', () {
    expect(saved('deepFilter').noiseSuppression, NoiseSuppression.dpdfnet);
  });

  test('RNNoise saved before DPDFNet was the default moves to it once', () {
    final before = const AppState().toJson()
      ..['noiseSuppression'] = 'rnnoise'
      ..remove('movedToDpdfnet');
    final moved = AppState.fromJson(before);
    expect(moved.noiseSuppression, NoiseSuppression.dpdfnet);

    // Picked again afterwards, it stays.
    final picked = moved.copyWith(noiseSuppression: NoiseSuppression.rnnoise);
    expect(
      AppState.fromJson(picked.toJson()).noiseSuppression,
      NoiseSuppression.rnnoise,
    );
  });

  test('the move leaves every other saved choice alone', () {
    for (final mode in NoiseSuppression.values) {
      if (mode == NoiseSuppression.rnnoise) continue;
      final before = AppState(noiseSuppression: mode).toJson()
        ..remove('movedToDpdfnet');
      expect(AppState.fromJson(before).noiseSuppression, mode);
    }
  });

  test('a new install starts on DPDFNet-2', () {
    expect(const AppState().dpdfnetSmall, isTrue);
    final json = const AppState().toJson()..remove('dpdfnetSmall');
    expect(AppState.fromJson(json).dpdfnetSmall, isTrue);
  });

  test('DPDFNet-8 saved before DPDFNet-2 was the default moves to it once', () {
    final before = const AppState(dpdfnetSmall: false).toJson()
      ..remove('movedToDpdfnet2');
    final moved = AppState.fromJson(before);
    expect(moved.dpdfnetSmall, isTrue);

    // Picked again afterwards, it stays.
    final picked = moved.copyWith(dpdfnetSmall: false);
    expect(AppState.fromJson(picked.toJson()).dpdfnetSmall, isFalse);
  });

  test('a missing or unknown value reads as the default', () {
    final json = const AppState().toJson()..remove('noiseSuppression');
    expect(AppState.fromJson(json).noiseSuppression, NoiseSuppression.dpdfnet);
    expect(saved('krisp').noiseSuppression, NoiseSuppression.dpdfnet);
  });

  test('the model starts on Time critical, and an older save reads so', () {
    const fresh = AppState();
    expect(fresh.noiseFilterPriority, NoiseFilterPriority.timeCritical);
    expect(fresh.preciseCallTiming, isFalse);
    final older = const AppState().toJson()
      ..remove('noiseFilterPlacement')
      ..remove('preciseCallTiming');
    final read = AppState.fromJson(older);
    expect(read.noiseFilterPriority, NoiseFilterPriority.timeCritical);
    expect(read.preciseCallTiming, isFalse);
  });

  test('what beta.10 saved does not hold anyone on Normal', () {
    // Beta.10 wrote its default into everyone's save, so a saved Normal says
    // nothing about what they chose.
    final beta10 = const AppState().toJson()
      ..remove('noiseFilterPlacement')
      ..['noiseFilterPriority'] = 'normal';
    expect(
      AppState.fromJson(beta10).noiseFilterPriority,
      NoiseFilterPriority.timeCritical,
    );
  });

  test('each beta option survives a JSON round-trip', () {
    for (final priority in NoiseFilterPriority.values) {
      final state = AppState(
        noiseFilterPriority: priority,
        preciseCallTiming: true,
      );
      final read = AppState.fromJson(state.toJson());
      expect(read.noiseFilterPriority, priority);
      expect(read.preciseCallTiming, isTrue);
    }
    final unknown = const AppState().toJson()
      ..['noiseFilterPlacement'] = 'realtime';
    expect(
      AppState.fromJson(unknown).noiseFilterPriority,
      NoiseFilterPriority.timeCritical,
    );
  });

  test('Linux offers only the capture thread beside Normal', () {
    expect(
      NoiseFilterPriority.offered(windows: true),
      NoiseFilterPriority.values,
    );
    expect(NoiseFilterPriority.offered(windows: false), [
      NoiseFilterPriority.timeCritical,
      NoiseFilterPriority.normal,
    ]);
  });
}
