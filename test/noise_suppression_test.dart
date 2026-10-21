import 'package:flutter_test/flutter_test.dart';
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

  test('a missing or unknown value reads as the default', () {
    final json = const AppState().toJson()..remove('noiseSuppression');
    expect(AppState.fromJson(json).noiseSuppression, NoiseSuppression.dpdfnet);
    expect(saved('krisp').noiseSuppression, NoiseSuppression.dpdfnet);
  });
}
