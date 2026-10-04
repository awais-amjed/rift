/// What cleans the microphone up before it reaches a call.
///
/// [standard] is libwebrtc's own suppressor, which every platform has. The
/// others are models run on this device inside libwebrtc's processing, where
/// the platform has them (`NoiseFilter`); elsewhere they fall back to
/// [standard]. A model replaces the built-in suppressor rather than running
/// after it: the two together thin out the voice for no less noise.
enum NoiseSuppression {
  off,
  standard,
  rnnoise,
  deepFilter;

  String get label => switch (this) {
    off => 'Off',
    standard => 'Standard',
    rnnoise => 'RNNoise',
    deepFilter => 'DeepFilterNet',
  };

  /// Reads a saved value. Before there was a choice this was a switch, saved
  /// as a bool: on was the default nearly everyone kept, so it reads as the
  /// default now, and off stays off.
  static NoiseSuppression fromJson(Object? value) => switch (value) {
    false => off,
    String name => values.asNameMap()[name] ?? rnnoise,
    _ => rnnoise,
  };

  String toJson() => name;
}
