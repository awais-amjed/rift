/// What the noise filter is busy with, for settings to say so while a choice
/// takes effect. A choice that seems to do nothing gets picked again.
enum NoiseFilterWork {
  none,

  /// At start, waiting for the runner to put its filter on the microphone.
  /// On Windows Dart starts first, so the filter turns up a moment later.
  starting,

  /// The chosen model's files coming down, the first time it is picked.
  /// Standard stands in meanwhile, or RNNoise for DPDFNet when it is here.
  downloadingModel,

  /// The chosen model's files did not come down. What stands in meanwhile
  /// stays on until they do.
  modelUnavailable,

  /// The chosen model loading from files already here.
  loadingModel,
}
