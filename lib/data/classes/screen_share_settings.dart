import 'package:equatable/equatable.dart';

import '../../src/rust/api/screenshare/types.dart';
import 'server_limits.dart';
import 'share_encoding.dart';
import 'share_sound_choice.dart';

/// Over the model budget and one job: a share's settings, each with its JSON
/// key, default and the rule for what it sends.
///
/// What the next screen share will send, remembered between calls. The source
/// fields are per-platform: a window index and title everywhere, a PID on
/// Windows, a PulseAudio source on Linux.
class ScreenShareSettings extends Equatable {
  final int resolution; // height in px, one of [resolutions] on a desktop
  final int fps;

  /// In Mbps, used only when [bitrateChosen]; otherwise Auto sets it from
  /// the picture ([bitrateToSend]).
  final int bitrate;

  /// Whether [bitrate] was picked by hand rather than left on Auto.
  final bool bitrateChosen;
  final bool shareAudio;
  final bool captureFullScreen; // true = full screen, false = window
  /// Where the chosen source sat in the list it was picked from. Only the
  /// share started from that same list may use it: windows open and close in
  /// between, so in the next list it can name somebody else's window.
  final int? selectedVideoSourceIndex;
  final int? selectedVideoSourcePid; // the window's process: Windows and X11

  /// The chosen source's title, which is what finds it again in a later list.
  final String? selectedVideoSourceTitle;

  /// X11: the chosen window's app, which a remembered sound is kept under.
  final String? selectedVideoSourceAppId;
  final String codec; // "VP8", "H264", "H265" or "VP9", as the picker shows it

  /// Whether [codec] was picked by hand. One that was not is Auto, which
  /// follows the hardware and the priority (see [codecToSend]).
  final bool codecChosen;

  /// Whether a phone's dialog shows its advanced settings (codec, bitrate).
  /// Somebody who opened them once wants them there the next time.
  final bool showsAdvanced;

  /// What the share gives up when it cannot keep up: frames or sharpness.
  final SharePriority priority;

  /// Whether the mouse cursor is in the picture.
  final ShareCursor cursor;
  final AudioSource? selectedAudioSource; // Linux PulseAudio source

  /// Whether a phone's or a browser's dialog has confirmed these. Until then
  /// they are the defaults above, written for a desktop, which neither opens
  /// on (`PhoneShare.opening`, `WebShare.opening`). The name is from before a
  /// browser had a dialog, kept so saved settings keep it.
  final bool phoneSetUp;

  /// Linux: the sound a window of each app is shared with, by the app's id,
  /// or by the window's title where the desktop did not say whose it is
  /// (`ShareSoundMatch.appKey`), for the ones the user said to remember.
  final Map<String, ShareSoundChoice> soundForApps;

  const ScreenShareSettings({
    this.resolution = 1080,
    this.fps = 60,
    this.bitrate = defaultMbps,
    this.bitrateChosen = false,
    this.shareAudio = true,
    this.captureFullScreen = true,
    this.selectedVideoSourceIndex,
    this.selectedVideoSourcePid,
    this.selectedVideoSourceTitle,
    this.selectedVideoSourceAppId,
    this.codec = 'VP9',
    this.codecChosen = false,
    this.showsAdvanced = false,
    this.priority = defaultPriority,
    this.cursor = ShareCursor.auto,
    this.selectedAudioSource,
    this.phoneSetUp = false,
    this.soundForApps = const {},
  });

  /// The bitrate every share started at before there was Auto.
  static const defaultMbps = 10;

  /// Settings saved before Auto existed have no flag saying whether a value
  /// was picked. One still at the old default counts as never picked, and
  /// goes to Auto; one changed from it was a choice, and is kept.
  factory ScreenShareSettings.fromJson(Map<String, dynamic> json) {
    final codec = json['codec'] as String? ?? 'VP9';
    final bitrate = json['bitrate'] as int? ?? defaultMbps;
    return ScreenShareSettings(
      resolution: json['resolution'] as int? ?? 1080,
      fps: json['fps'] as int? ?? 60,
      bitrate: bitrate,
      bitrateChosen: json['bitrateChosen'] as bool? ?? bitrate != defaultMbps,
      shareAudio: json['shareAudio'] as bool? ?? true,
      captureFullScreen: json['captureFullScreen'] as bool? ?? true,
      selectedVideoSourceIndex: json['selectedVideoSourceIndex'] as int?,
      selectedVideoSourcePid: json['selectedVideoSourcePid'] as int?,
      selectedVideoSourceTitle: json['selectedVideoSourceTitle'] as String?,
      selectedVideoSourceAppId: json['selectedVideoSourceAppId'] as String?,
      codec: codec,
      codecChosen:
          json['codecChosen'] as bool? ?? codecFromName(codec) != defaultCodec,
      showsAdvanced: json['showsAdvanced'] as bool? ?? false,
      priority: priorityFromName(json['priority'] as String?),
      cursor:
          ShareCursor.values.asNameMap()[json['cursor'] as String?] ??
          ShareCursor.auto,
      phoneSetUp: json['phoneSetUp'] as bool? ?? false,
      // selectedAudioSource is not persisted in JSON (runtime only)
      soundForApps: {
        for (final entry
            in (json['soundForApps'] as Map<String, dynamic>? ?? {}).entries)
          entry.key: ShareSoundChoice.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'resolution': resolution,
    'fps': fps,
    'bitrate': bitrate,
    'bitrateChosen': bitrateChosen,
    'shareAudio': shareAudio,
    'captureFullScreen': captureFullScreen,
    'selectedVideoSourceIndex': selectedVideoSourceIndex,
    'selectedVideoSourcePid': selectedVideoSourcePid,
    'selectedVideoSourceTitle': selectedVideoSourceTitle,
    'selectedVideoSourceAppId': selectedVideoSourceAppId,
    'codec': codec,
    'codecChosen': codecChosen,
    'showsAdvanced': showsAdvanced,
    'priority': priority.name,
    'cursor': cursor.name,
    'phoneSetUp': phoneSetUp,
    'soundForApps': {
      for (final entry in soundForApps.entries) entry.key: entry.value.toJson(),
    },
  };

  /// [codec] as the Rust side takes it. The string is what is persisted and
  /// shown, so an unknown one — an old build's "AV1", a hand-edited file —
  /// falls back to the default rather than failing at share time.
  VideoCodec get videoCodec => codecFromName(codec);

  static const defaultCodec = VideoCodec.vp9;

  static VideoCodec codecFromName(String name) => switch (name.toUpperCase()) {
    'H264' => VideoCodec.h264,
    'H265' => VideoCodec.h265,
    'VP8' => VideoCodec.vp8,
    'VP9' => VideoCodec.vp9,
    _ => defaultCodec,
  };

  /// The codecs the picker offers besides Auto. Where H264 is only ever
  /// encoded on the GPU ([gpuOnlyH264]), it is offered only if the GPU
  /// encodes it ([gpu]), and H265 only ever comes from there; VP8 and VP9 are
  /// always there, encoded on the CPU.
  static List<VideoCodec> codecsOffered({
    required bool gpuOnlyH264,
    required Set<VideoCodec> gpu,
  }) => [
    VideoCodec.vp8,
    if (!gpuOnlyH264 || gpu.contains(VideoCodec.h264)) VideoCodec.h264,
    if (gpu.contains(VideoCodec.h265)) VideoCodec.h265,
    VideoCodec.vp9,
  ];

  /// The codec a share goes out in.
  ///
  /// Auto ([codecChosen] false) is [ShareEncoding.autoCodec]: H264 only where
  /// it is only ever encoded on the GPU ([gpuOnlyH264]) and the GPU encodes
  /// it, since elsewhere nothing says a hardware encoder is there, and H265
  /// where the GPU encodes that too. A codec picked by hand is sent as picked,
  /// except an H264 with no GPU to encode it where it is GPU-only: that goes
  /// out as VP9, rather than as H264 encoded on the CPU. A saved H265 the GPU
  /// here does not encode goes out as the next best of the two.
  VideoCodec codecToSend({
    required bool gpuOnlyH264,
    required Set<VideoCodec> gpu,
  }) {
    final gpuH264 = gpuOnlyH264 && gpu.contains(VideoCodec.h264);
    final gpuH265 = gpuH264 && gpu.contains(VideoCodec.h265);
    if (!codecChosen) {
      return ShareEncoding.autoCodec(
        priority: priority,
        gpuH264: gpuH264,
        gpuH265: gpuH265,
      );
    }
    final saved = codecFromName(codec);
    if (saved == VideoCodec.h265 && !gpuH265) {
      return gpuH264 ? VideoCodec.h264 : VideoCodec.vp9;
    }
    if (gpuOnlyH264 && saved == VideoCodec.h264 && !gpuH264) {
      return VideoCodec.vp9;
    }
    return saved;
  }

  /// The bitrate a share in [codec] goes out at, in Mbps: the one picked by
  /// hand, or Auto's for the picture, and never more than the server allows.
  /// [h264High] is whether this computer's H264 goes out in High profile, which
  /// needs less for the same picture.
  int bitrateToSend({
    required VideoCodec codec,
    required ServerLimits limits,
    bool h264High = false,
  }) => limits.shareMbps(
    bitrateChosen
        ? bitrate
        : ShareEncoding.autoMbps(
            resolution: resolution,
            fps: fpsToSend,
            codec: codec,
            h264High: h264High,
          ),
  );

  /// The tallest picture 120 fps is offered for. Past 2K it is more than
  /// most viewers' hardware decoders take (H264's level 5.2 ends near 4K60);
  /// up to it, whether the sharer's computer keeps up is the sharer's call.
  static const maxHeightAt120 = 1440;

  /// The frame rates [frameRates] offers for a picture [resolution] tall.
  static List<int> frameRatesAt(int resolution) => [
    for (final rate in frameRates)
      if (rate <= 60 || resolution <= maxHeightAt120) rate,
  ];

  /// The frame rate a share goes out at: [fps], or 60 where 120 is not
  /// offered for this picture ([frameRatesAt]). The choice itself is kept,
  /// so going back to a smaller picture brings 120 back.
  int get fpsToSend => frameRatesAt(resolution).contains(fps) ? fps : 60;

  /// A codec as the picker and the summary name it.
  static String nameOf(VideoCodec codec) => codec.name.toUpperCase();

  /// Smoothness, because a stream is usually something moving: LiveKit's own
  /// default for a screen share drops frames to stay sharp, and a game
  /// stutters.
  static const defaultPriority = SharePriority.smoothness;

  /// A stored priority, by its name. Saved settings from before there was one,
  /// and a name this build does not know, get the default.
  static SharePriority priorityFromName(String? name) =>
      SharePriority.values.asNameMap()[name] ?? defaultPriority;

  /// The heights offered, by the picker and by the menu on a running share.
  static const resolutions = [360, 480, 720, 1080, 1440, 2160];

  /// The frame rates offered, in the same two places.
  static const frameRates = [15, 30, 60, 120];

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
        bitrateChosen: bitrateChosen,
        shareAudio: shareAudio,
        captureFullScreen: captureFullScreen,
        selectedVideoSourceIndex: source.index,
        selectedVideoSourcePid: source.audioSourcePid,
        selectedVideoSourceTitle: source.title,
        selectedVideoSourceAppId: source.appId,
        codec: codec,
        codecChosen: codecChosen,
        showsAdvanced: showsAdvanced,
        priority: priority,
        cursor: cursor,
        selectedAudioSource: selectedAudioSource,
        phoneSetUp: phoneSetUp,
        soundForApps: soundForApps,
      );

  /// Passing null keeps the current value, so removing a selection needs an
  /// explicit [clearVideoSource] / [clearAudioSource] — the settings dialog
  /// does exactly that when you switch between screen and window capture.
  ScreenShareSettings copyWith({
    int? resolution,
    int? fps,
    int? bitrate,
    bool? bitrateChosen,
    bool? shareAudio,
    bool? captureFullScreen,
    int? selectedVideoSourceIndex,
    int? selectedVideoSourcePid,
    String? selectedVideoSourceTitle,
    String? selectedVideoSourceAppId,
    String? codec,
    bool? codecChosen,
    bool? showsAdvanced,
    SharePriority? priority,
    ShareCursor? cursor,
    AudioSource? selectedAudioSource,
    bool? phoneSetUp,
    Map<String, ShareSoundChoice>? soundForApps,
    bool clearVideoSource = false,
    bool clearAudioSource = false,
  }) {
    return ScreenShareSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      bitrateChosen: bitrateChosen ?? this.bitrateChosen,
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
      selectedVideoSourceAppId: clearVideoSource
          ? null
          : selectedVideoSourceAppId ?? this.selectedVideoSourceAppId,
      codec: codec ?? this.codec,
      codecChosen: codecChosen ?? this.codecChosen,
      showsAdvanced: showsAdvanced ?? this.showsAdvanced,
      priority: priority ?? this.priority,
      cursor: cursor ?? this.cursor,
      selectedAudioSource: clearAudioSource
          ? null
          : selectedAudioSource ?? this.selectedAudioSource,
      phoneSetUp: phoneSetUp ?? this.phoneSetUp,
      soundForApps: soundForApps ?? this.soundForApps,
    );
  }

  @override
  List<Object?> get props => [
    resolution,
    fps,
    bitrate,
    bitrateChosen,
    shareAudio,
    captureFullScreen,
    selectedVideoSourceIndex,
    selectedVideoSourcePid,
    selectedVideoSourceTitle,
    selectedVideoSourceAppId,
    codec,
    codecChosen,
    showsAdvanced,
    priority,
    cursor,
    selectedAudioSource,
    phoneSetUp,
    soundForApps,
  ];
}
