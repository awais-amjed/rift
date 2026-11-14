part of 'models_cubit.dart';

class ModelsState extends Equatable {
  /// Each model downloading or failed, by its local name. A model that
  /// lands is taken out.
  final Map<String, ModelProgress> unfinished;

  const ModelsState({required this.unfinished});

  static const empty = ModelsState(unfinished: {});

  /// This state, told of [progress].
  ModelsState after(ModelProgress progress) {
    final next = Map.of(unfinished);
    if (progress.status == ModelStatus.success) {
      next.remove(progress.file.localName);
    } else {
      next[progress.file.localName] = progress;
    }
    return ModelsState(unfinished: next);
  }

  ModelsState afterAll(Iterable<ModelProgress> progress) =>
      progress.fold(this, (state, p) => state.after(p));

  /// The models coming down now.
  List<ModelFile> get loading => [
    for (final p in unfinished.values)
      if (p.status == ModelStatus.loading) p.file,
  ];

  /// The models whose last try failed.
  List<ModelFile> get failed => [
    for (final p in unfinished.values)
      if (p.status == ModelStatus.failure) p.file,
  ];

  /// How far the downloads running now have come together, 0 to 1, by bytes:
  /// a large model weighs more than a small one.
  double get fraction => fractionOf(null);

  /// [fraction], of [files] alone: one model's files, beside another's
  /// downloading at the same time.
  double fractionOf(Set<ModelFile>? files) {
    var size = 0, received = 0;
    for (final p in unfinished.values) {
      if (p.status != ModelStatus.loading) continue;
      if (files != null && !files.contains(p.file)) continue;
      size += p.file.size;
      received += p.received.clamp(0, p.file.size);
    }
    return size == 0 ? 0 : received / size;
  }

  @override
  List<Object?> get props => [unfinished];
}
