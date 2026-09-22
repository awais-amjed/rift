import '../../src/rust/api/screenshare/types.dart';

/// What the next screen share will send, remembered between calls. The source
/// fields are per-platform: a window index everywhere, a PID on Windows, a
/// PulseAudio source on Linux.
class ScreenShareSettings {
  final int resolution; // height in px (720, 1080, 1440, 2160)
  final int fps;
  final int bitrate; // in Mbps
  final bool shareAudio;
  final bool captureFullScreen; // true = full screen, false = window
  final int? selectedVideoSourceIndex;
  final int? selectedVideoSourcePid; // Windows-only PID for selected window
  final String codec; // "VP8", "H264" or "VP9", as the picker shows it
  final AudioSource? selectedAudioSource; // Linux PulseAudio source

  const ScreenShareSettings({
    this.resolution = 1080,
    this.fps = 60,
    this.bitrate = 10,
    this.shareAudio = true,
    this.captureFullScreen = true,
    this.selectedVideoSourceIndex,
    this.selectedVideoSourcePid,
    this.codec = 'VP9',
    this.selectedAudioSource,
  });

  factory ScreenShareSettings.fromJson(Map<String, dynamic> json) {
    return ScreenShareSettings(
      resolution: json['resolution'] as int? ?? 1080,
      fps: json['fps'] as int? ?? 60,
      bitrate: json['bitrate'] as int? ?? 10,
      shareAudio: json['shareAudio'] as bool? ?? true,
      captureFullScreen: json['captureFullScreen'] as bool? ?? true,
      selectedVideoSourceIndex: json['selectedVideoSourceIndex'] as int?,
      selectedVideoSourcePid: json['selectedVideoSourcePid'] as int?,
      codec: json['codec'] as String? ?? 'VP9',
      // selectedAudioSource is not persisted in JSON (runtime only)
    );
  }

  Map<String, dynamic> toJson() => {
    'resolution': resolution,
    'fps': fps,
    'bitrate': bitrate,
    'shareAudio': shareAudio,
    'captureFullScreen': captureFullScreen,
    'selectedVideoSourceIndex': selectedVideoSourceIndex,
    'selectedVideoSourcePid': selectedVideoSourcePid,
    'codec': codec,
  };

  /// [codec] as the Rust side takes it. The string is what is persisted and
  /// shown, so an unknown one — an old build's "AV1", a hand-edited file —
  /// falls back to the default rather than failing at share time.
  VideoCodec get videoCodec => codecFromName(codec);

  static const defaultCodec = VideoCodec.vp9;

  static VideoCodec codecFromName(String name) => switch (name.toUpperCase()) {
    'H264' => VideoCodec.h264,
    'VP8' => VideoCodec.vp8,
    'VP9' => VideoCodec.vp9,
    _ => defaultCodec,
  };

  /// Human label for [resolution], as shown in the settings summary.
  String get resolutionLabel => switch (resolution) {
    720 => '720p',
    1080 => '1080p',
    1440 => '2K',
    2160 => '4K',
    _ => '${resolution}p',
  };

  /// Passing null keeps the current value, so removing a selection needs an
  /// explicit [clearVideoSource] / [clearAudioSource] — the settings dialog
  /// does exactly that when you switch between screen and window capture.
  ScreenShareSettings copyWith({
    int? resolution,
    int? fps,
    int? bitrate,
    bool? shareAudio,
    bool? captureFullScreen,
    int? selectedVideoSourceIndex,
    int? selectedVideoSourcePid,
    String? codec,
    AudioSource? selectedAudioSource,
    bool clearVideoSource = false,
    bool clearAudioSource = false,
  }) {
    return ScreenShareSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      shareAudio: shareAudio ?? this.shareAudio,
      captureFullScreen: captureFullScreen ?? this.captureFullScreen,
      selectedVideoSourceIndex: clearVideoSource
          ? null
          : selectedVideoSourceIndex ?? this.selectedVideoSourceIndex,
      selectedVideoSourcePid: clearVideoSource
          ? null
          : selectedVideoSourcePid ?? this.selectedVideoSourcePid,
      codec: codec ?? this.codec,
      selectedAudioSource: clearAudioSource
          ? null
          : selectedAudioSource ?? this.selectedAudioSource,
    );
  }
}
