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
