import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

void main() {
  test('capturing on the GPU is on by default', () {
    expect(const AppState().gpuScreenCapture, isTrue);
  });

  test('a state saved before the switch existed has it on', () {
    final saved = const AppState().toJson()..remove('gpuScreenCapture');
    expect(AppState.fromJson(saved).gpuScreenCapture, isTrue);
  });

  test('turning it off survives a restart', () {
    final saved = const AppState().copyWith(gpuScreenCapture: false).toJson();
    expect(AppState.fromJson(saved).gpuScreenCapture, isFalse);
  });
}
