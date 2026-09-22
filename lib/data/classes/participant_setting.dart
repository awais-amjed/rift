/// This device's own mute and volume for one person, one shared sound, or one
/// pair of call cues (`CallSound`). Nobody else sees it and no server stores
/// it; it persists in `AppState`.
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
