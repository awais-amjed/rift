part of 'app_cubit.dart';

class AppState {
  // ── Persisted ──────────────────────────────────────────────
  final bool isPinned;
  final bool audioEnabled;
  final bool videoEnabled;
  final ScreenShareSettings screenShareSettings;
  final Map<String, ParticipantSetting> participantSettings;

  // ── Transient (not stored in JSON) ─────────────────────────
  final bool isHovered;
  final String? selectedChannelId;
  final List<ParticipantInfo> participants;

  const AppState({
    this.isPinned = true,
    this.audioEnabled = true,
    this.videoEnabled = false,
    this.screenShareSettings = const ScreenShareSettings(),
    this.participantSettings = const {},
    this.isHovered = false,
    this.selectedChannelId,
    this.participants = const [],
  });

  AppState copyWith({
    bool? isPinned,
    bool? audioEnabled,
    bool? videoEnabled,
    ScreenShareSettings? screenShareSettings,
    Map<String, ParticipantSetting>? participantSettings,
    bool? isHovered,
    String? selectedChannelId,
    bool clearSelectedChannelId = false,
    List<ParticipantInfo>? participants,
  }) {
    return AppState(
      isPinned: isPinned ?? this.isPinned,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      videoEnabled: videoEnabled ?? this.videoEnabled,
      screenShareSettings: screenShareSettings ?? this.screenShareSettings,
      participantSettings: participantSettings ?? this.participantSettings,
      isHovered: isHovered ?? this.isHovered,
      selectedChannelId: clearSelectedChannelId
          ? null
          : (selectedChannelId ?? this.selectedChannelId),
      participants: participants ?? this.participants,
    );
  }

  factory AppState.fromJson(Map<String, dynamic> json) {
    final settingsMap = <String, ParticipantSetting>{};
    final raw = json['participantSettings'] as Map<String, dynamic>?;
    if (raw != null) {
      raw.forEach((key, value) {
        settingsMap[key] = ParticipantSetting.fromJson(
          value as Map<String, dynamic>,
        );
      });
    }

    return AppState(
      isPinned: json['isPinned'] as bool? ?? true,
      audioEnabled: json['audioEnabled'] as bool? ?? true,
      videoEnabled: json['videoEnabled'] as bool? ?? false,
      screenShareSettings: json['screenShareSettings'] != null
          ? ScreenShareSettings.fromJson(
              json['screenShareSettings'] as Map<String, dynamic>,
            )
          : const ScreenShareSettings(),
      participantSettings: settingsMap,
    );
  }

  Map<String, dynamic> toJson() => {
    'isPinned': isPinned,
    'audioEnabled': audioEnabled,
    'videoEnabled': videoEnabled,
    'screenShareSettings': screenShareSettings.toJson(),
    'participantSettings': participantSettings.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };
}
