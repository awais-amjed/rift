import '../../src/rust/api/screenshare/types.dart';

/// What the next screen share will send, remembered between calls. The source
/// fields are per-platform: a window index and title everywhere, a PID on
/// Windows, a PulseAudio source on Linux.
class ScreenShareSettings {
  final int resolution; // height in px (720, 1080, 1440, 2160)
  final int fps;
  final int bitrate; // in Mbps
  final bool shareAudio;
  final bool captureFullScreen; // true = full screen, false = window
  /// Where the chosen source sat in the list it was picked from. Only the
  /// share started from that same list may use it: windows open and close in
  /// between, so in the next list it can name somebody else's window.
  final int? selectedVideoSourceIndex;
  final int? selectedVideoSourcePid; // Windows-only PID for selected window

  /// The chosen source's title, which is what finds it again in a later list.
  final String? selectedVideoSourceTitle;
  final String codec; // "VP8", "H264" or "VP9", as the picker shows it

  /// Whether [codec] was picked by hand. One that was not follows the
  /// hardware where it can (see [codecToSend]).
  final bool codecChosen;

  /// What the share gives up when it cannot keep up: frames or sharpness.
  final SharePriority priority;
  final AudioSource? selectedAudioSource; // Linux PulseAudio source

  const ScreenShareSettings({
    this.resolution = 1080,
    this.fps = 60,
    this.bitrate = 10,
    this.shareAudio = true,
    this.captureFullScreen = true,
    this.selectedVideoSourceIndex,
    this.selectedVideoSourcePid,
    this.selectedVideoSourceTitle,
    this.codec = 'VP9',
    this.codecChosen = false,
    this.priority = defaultPriority,
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
      selectedVideoSourceTitle: json['selectedVideoSourceTitle'] as String?,
      codec: json['codec'] as String? ?? 'VP9',
      codecChosen: json['codecChosen'] as bool? ?? false,
      priority: priorityFromName(json['priority'] as String?),
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
    'selectedVideoSourceTitle': selectedVideoSourceTitle,
    'codec': codec,
    'codecChosen': codecChosen,
    'priority': priority.name,
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

  /// The codecs the picker offers, by name. Where H264 is only ever encoded
  /// on the GPU ([gpuOnlyH264]), it is offered only if the GPU encodes it
  /// ([gpu]); VP8 and VP9 are always there, encoded on the CPU.
  static List<String> codecsOffered({
    required bool gpuOnlyH264,
    required Set<VideoCodec> gpu,
  }) => [
    'VP8',
    if (!gpuOnlyH264 || gpu.contains(VideoCodec.h264)) 'H264',
    'VP9',
  ];

  /// The codec a share goes out in, by name, which is what the picker shows
  /// as chosen.
  ///
  /// Where H264 is only ever encoded on the GPU ([gpuOnlyH264]): a codec
  /// never picked by hand follows the hardware, H264 where the GPU encodes it
  /// and VP9 elsewhere; a saved H264 with no GPU to encode it goes out as
  /// VP9, rather than as H264 encoded on the CPU. Settings saved before there
  /// was a choice to follow hold the old default, VP9, unpicked. Elsewhere
  /// the saved codec, as it always was.
  String codecToSend({
    required bool gpuOnlyH264,
    required Set<VideoCodec> gpu,
  }) {
    final saved = codecFromName(codec);
    if (!gpuOnlyH264) return saved.name.toUpperCase();
    final gpuH264 = gpu.contains(VideoCodec.h264);
    if (!codecChosen && saved == defaultCodec) return gpuH264 ? 'H264' : 'VP9';
    if (saved == VideoCodec.h264 && !gpuH264) return 'VP9';
    return saved.name.toUpperCase();
  }

  /// Smoothness, because a stream is usually something moving: LiveKit's own
  /// default for a screen share drops frames to stay sharp, and a game
  /// stutters.
  static const defaultPriority = SharePriority.smoothness;

  /// A stored priority, by its name. Saved settings from before there was one,
  /// and a name this build does not know, get the default.
  static SharePriority priorityFromName(String? name) =>
      SharePriority.values.asNameMap()[name] ?? defaultPriority;

  /// The heights offered, by the picker and by the menu on a running share.
  static const resolutions = [720, 1080, 1440, 2160];

  /// The frame rates offered, in the same two places.
  static const frameRates = [15, 30, 60];

  /// Human label for [resolution], as shown in the settings summary.
  String get resolutionLabel => labelFor(resolution);

  /// Human label for a height in [resolutions].
  static String labelFor(int resolution) => switch (resolution) {
    720 => '720p',
    1080 => '1080p',
    1440 => '2K',
    2160 => '4K',
    _ => '${resolution}p',
  };

  /// [source] as the one to share, replacing every part of the last choice —
  /// a window without a process must not keep the previous window's.
  ScreenShareSettings withVideoSource(CaptureSource source) =>
      ScreenShareSettings(
        resolution: resolution,
        fps: fps,
        bitrate: bitrate,
        shareAudio: shareAudio,
        captureFullScreen: captureFullScreen,
        selectedVideoSourceIndex: source.index,
        selectedVideoSourcePid: source.audioSourcePid,
        selectedVideoSourceTitle: source.title,
        codec: codec,
        codecChosen: codecChosen,
        priority: priority,
        selectedAudioSource: selectedAudioSource,
      );

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
    String? selectedVideoSourceTitle,
    String? codec,
    bool? codecChosen,
    SharePriority? priority,
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
      selectedVideoSourceTitle: clearVideoSource
          ? null
          : selectedVideoSourceTitle ?? this.selectedVideoSourceTitle,
      codec: codec ?? this.codec,
      codecChosen: codecChosen ?? this.codecChosen,
      priority: priority ?? this.priority,
      selectedAudioSource: clearAudioSource
          ? null
          : selectedAudioSource ?? this.selectedAudioSource,
    );
  }
}
