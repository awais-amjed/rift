/// What the noise filter is busy with, for settings to say so while a choice
/// takes effect. Neither lasts long, but a choice that seems to do nothing
/// gets picked again.
enum NoiseFilterWork {
  none,

  /// At start, waiting for the runner to put its filter on the microphone.
  /// On Windows Dart starts first, so the filter turns up a moment later.
  starting,

  /// DPDFNet loading, the first time it is picked.
  loadingModel;

  /// Whether the wait for the runner's filter ended between this and [now]:
  /// what was set up without it, with libwebrtc's suppressor standing in, is
  /// set up again.
  bool startedSince(NoiseFilterWork now) => this == starting && now != starting;
}
