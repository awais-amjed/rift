part of 'app_cubit.dart';

@JsonSerializable(explicitToJson: true)
class AppState {
  // ── Persisted ──────────────────────────────────────────────
  final bool isPinned;
  final bool audioEnabled;
  final bool videoEnabled;
  final bool pushToTalkEnabled;
  final int? pushToTalkKeyId;
  final String? pushToTalkKeyLabel;
  final bool titleBarVisible;
  final ScreenShareSettings screenShareSettings;
  final Map<String, ParticipantSetting> participantSettings;
  final double? windowWidth;
  final double? windowHeight;
  final double? windowX;
  final double? windowY;
  final bool disableAudioDucking;
  final bool statsOverlayPinned;
  final String? outputDeviceId;

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
    this.pushToTalkEnabled = false,
    this.pushToTalkKeyId,
    this.pushToTalkKeyLabel,
    this.titleBarVisible = true,
    this.screenShareSettings = const ScreenShareSettings(),
    this.participantSettings = const {},
    this.windowWidth,
    this.windowHeight,
    this.windowX,
    this.windowY,
    this.disableAudioDucking = false,
    this.statsOverlayPinned = false,
    this.outputDeviceId,
    this.isHovered = false,
    this.selectedChannelId,
    this.participants = const [],
  });

  AppState copyWith({
    bool? isPinned,
    bool? audioEnabled,
    bool? videoEnabled,
    bool? pushToTalkEnabled,
    int? pushToTalkKeyId,
    String? pushToTalkKeyLabel,
    bool clearPushToTalkKeybind = false,
    bool? titleBarVisible,
    ScreenShareSettings? screenShareSettings,
    Map<String, ParticipantSetting>? participantSettings,
    double? windowWidth,
    double? windowHeight,
    double? windowX,
    double? windowY,
    bool? disableAudioDucking,
    bool? statsOverlayPinned,
    String? outputDeviceId,
    bool clearOutputDeviceId = false,
    bool? isHovered,
    String? selectedChannelId,
    bool clearSelectedChannelId = false,
    List<ParticipantInfo>? participants,
  }) {
    return AppState(
      isPinned: isPinned ?? this.isPinned,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      videoEnabled: videoEnabled ?? this.videoEnabled,
      pushToTalkEnabled: pushToTalkEnabled ?? this.pushToTalkEnabled,
      pushToTalkKeyId: clearPushToTalkKeybind
          ? null
          : (pushToTalkKeyId ?? this.pushToTalkKeyId),
      pushToTalkKeyLabel: clearPushToTalkKeybind
          ? null
          : (pushToTalkKeyLabel ?? this.pushToTalkKeyLabel),
      titleBarVisible: titleBarVisible ?? this.titleBarVisible,
      screenShareSettings: screenShareSettings ?? this.screenShareSettings,
      participantSettings: participantSettings ?? this.participantSettings,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
      disableAudioDucking: disableAudioDucking ?? this.disableAudioDucking,
      statsOverlayPinned: statsOverlayPinned ?? this.statsOverlayPinned,
      outputDeviceId: clearOutputDeviceId ? null : (outputDeviceId ?? this.outputDeviceId),
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
