class ScreenShareSettings {
  final int resolution; // height in px (720, 1080, 1440, 2160)
  final int fps;
  final int bitrate; // in Mbps
  final bool shareAudio;

  const ScreenShareSettings({
    this.resolution = 1080,
    this.fps = 60,
    this.bitrate = 10,
    this.shareAudio = true,
  });

  factory ScreenShareSettings.fromJson(Map<String, dynamic> json) {
    return ScreenShareSettings(
      resolution: json['resolution'] as int? ?? 1080,
      fps: json['fps'] as int? ?? 60,
      bitrate: json['bitrate'] as int? ?? 10,
      shareAudio: json['shareAudio'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'resolution': resolution,
    'fps': fps,
    'bitrate': bitrate,
    'shareAudio': shareAudio,
  };

  ScreenShareSettings copyWith({
    int? resolution,
    int? fps,
    int? bitrate,
    bool? shareAudio,
  }) {
    return ScreenShareSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      shareAudio: shareAudio ?? this.shareAudio,
    );
  }
}

class ParticipantSetting {
  final bool muted;
  final double volume;

  const ParticipantSetting({this.muted = false, this.volume = 1.0});

  factory ParticipantSetting.fromJson(Map<String, dynamic> json) {
    return ParticipantSetting(
      muted: json['muted'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {'muted': muted, 'volume': volume};

  ParticipantSetting copyWith({bool? muted, double? volume}) {
    return ParticipantSetting(
      muted: muted ?? this.muted,
      volume: volume ?? this.volume,
    );
  }
}
