class ScreenShareSettings {
  final int resolution; // height in px (720, 1080, 1440, 2160)
  final int fps;
  final int bitrate; // in Mbps
  final bool shareAudio;
  final bool captureFullScreen; // true = full screen, false = window

  const ScreenShareSettings({
    this.resolution = 1080,
    this.fps = 60,
    this.bitrate = 10,
    this.shareAudio = true,
    this.captureFullScreen = true,
  });

  factory ScreenShareSettings.fromJson(Map<String, dynamic> json) {
    return ScreenShareSettings(
      resolution: json['resolution'] as int? ?? 1080,
      fps: json['fps'] as int? ?? 60,
      bitrate: json['bitrate'] as int? ?? 10,
      shareAudio: json['shareAudio'] as bool? ?? true,
      captureFullScreen: json['captureFullScreen'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'resolution': resolution,
    'fps': fps,
    'bitrate': bitrate,
    'shareAudio': shareAudio,
    'captureFullScreen': captureFullScreen,
  };

  ScreenShareSettings copyWith({
    int? resolution,
    int? fps,
    int? bitrate,
    bool? shareAudio,
    bool? captureFullScreen,
  }) {
    return ScreenShareSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      shareAudio: shareAudio ?? this.shareAudio,
      captureFullScreen: captureFullScreen ?? this.captureFullScreen,
    );
  }
}
