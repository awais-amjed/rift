import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/model_file.dart';
import 'package:rift/data/classes/model_progress.dart';
import 'package:rift/logic/cubits/models/models_cubit.dart';

void main() {
  const big = ModelFile(
    id: 'big',
    name: 'big model',
    published: 'big.v1.bin',
    size: 300,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  const small = ModelFile(
    id: 'small',
    name: 'small model',
    published: 'small.v1.bin',
    size: 100,
    sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  );

  test('the share is by bytes across the downloads running', () {
    final state = ModelsState.empty
        .after(const ModelProgress(big, 150, ModelStatus.loading))
        .after(const ModelProgress(small, 50, ModelStatus.loading));
    expect(state.loading, [big, small]);
    expect(state.fraction, 0.5);
  });

  test('a model that lands drops out', () {
    final state = ModelsState.empty
        .after(const ModelProgress(big, 150, ModelStatus.loading))
        .after(const ModelProgress(big, 300, ModelStatus.success));
    expect(state.unfinished, isEmpty);
    expect(state.fraction, 0);
  });

  test('a failed model is listed, and leaves the share', () {
    final state = ModelsState.empty
        .after(const ModelProgress(big, 150, ModelStatus.failure))
        .after(const ModelProgress(small, 25, ModelStatus.loading));
    expect(state.failed, [big]);
    expect(state.loading, [small]);
    expect(state.fraction, 0.25);
  });

  test('a retry moves a failed model back to loading', () {
    final state = ModelsState.empty.afterAll(const [
      ModelProgress(big, 150, ModelStatus.failure),
      ModelProgress(big, 160, ModelStatus.loading),
    ]);
    expect(state.failed, isEmpty);
    expect(state.loading, [big]);
  });
}
