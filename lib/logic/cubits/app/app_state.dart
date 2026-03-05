part of 'app_cubit.dart';

@JsonSerializable(explicitToJson: true)
class AppState {
  // ── Persisted ──────────────────────────────────────────────
  final bool isPinned;
  final bool audioEnabled;
  final bool videoEnabled;
  final ScreenShareSettings screenShareSettings;
  final Map<String, ParticipantSetting> participantSettings;

  // ── Transient (not stored in JSON) ─────────────────────────
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool isHovered;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? selectedChannelId;
  @JsonKey(includeFromJson: false, includeToJson: false)
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

  factory AppState.fromJson(Map<String, dynamic> json) =>
      _$AppStateFromJson(json);

  Map<String, dynamic> toJson() => _$AppStateToJson(this);
}
