import '../../src/rust/api/screenshare/audio_linux.dart';

class ScreenShareSettings {
  final int resolution; // height in px (720, 1080, 1440, 2160)
  final int fps;
  final int bitrate; // in Mbps
  final bool shareAudio;
  final bool captureFullScreen; // true = full screen, false = window
  final int? selectedVideoSourceIndex;
  final int? selectedVideoSourcePid; // Windows-only PID for selected window
  final String codec; // "VP8", "H264", "VP9", "AV1"
  final AudioSource? selectedAudioSource; // Linux PulseAudio source

  const ScreenShareSettings({
    this.resolution = 1080,
    this.fps = 60,
    this.bitrate = 10,
    this.shareAudio = true,
    this.captureFullScreen = true,
    this.selectedVideoSourceIndex,
    this.selectedVideoSourcePid,
    this.codec = 'VP8',
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
      codec: json['codec'] as String? ?? 'VP8',
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
  }) {
    return ScreenShareSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      shareAudio: shareAudio ?? this.shareAudio,
      captureFullScreen: captureFullScreen ?? this.captureFullScreen,
      selectedVideoSourceIndex:
          selectedVideoSourceIndex ?? this.selectedVideoSourceIndex,
      selectedVideoSourcePid:
          selectedVideoSourcePid ?? this.selectedVideoSourcePid,
      codec: codec ?? this.codec,
      selectedAudioSource: selectedAudioSource ?? this.selectedAudioSource,
    );
  }
}
