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

  /// Whether the right-hand member sidebar is expanded. Persisted so the
  /// layout survives a restart.
  final bool membersSidebarOpen;
  final String? outputDeviceId;
  final String? inputDeviceId;

  // ── Audio processing (applied to the mic capture track) ────
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGainControl;

  /// Voice-activity gate threshold, 0..1. In voice-activity mode (push-to-talk
  /// off) the mic only transmits when its input level is at or above this.
  /// 0 disables the gate (open mic — the previous behaviour).
  final double voiceActivityThreshold;

  // ── Transient (not stored in JSON) ─────────────────────────
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool isHovered;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? selectedChannelId;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final List<ParticipantInfo> participants;

  /// Which surface the centre pane is showing.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final HomeSurface surface;

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
    this.inputDeviceId,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.voiceActivityThreshold = 0.0,
    this.membersSidebarOpen = true,
    this.isHovered = false,
    this.selectedChannelId,
    this.participants = const [],
    this.surface = HomeSurface.server,
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
    String? inputDeviceId,
    bool clearInputDeviceId = false,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? autoGainControl,
    double? voiceActivityThreshold,
    bool? membersSidebarOpen,
    bool? isHovered,
    String? selectedChannelId,
    bool clearSelectedChannelId = false,
    List<ParticipantInfo>? participants,
    HomeSurface? surface,
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
      outputDeviceId: clearOutputDeviceId
          ? null
          : (outputDeviceId ?? this.outputDeviceId),
      inputDeviceId: clearInputDeviceId
          ? null
          : (inputDeviceId ?? this.inputDeviceId),
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      autoGainControl: autoGainControl ?? this.autoGainControl,
      voiceActivityThreshold:
          voiceActivityThreshold ?? this.voiceActivityThreshold,
      membersSidebarOpen: membersSidebarOpen ?? this.membersSidebarOpen,
      isHovered: isHovered ?? this.isHovered,
      selectedChannelId: clearSelectedChannelId
          ? null
          : (selectedChannelId ?? this.selectedChannelId),
      participants: participants ?? this.participants,
      surface: surface ?? this.surface,
    );
  }

  factory AppState.fromJson(Map<String, dynamic> json) =>
      _$AppStateFromJson(json);

  Map<String, dynamic> toJson() => _$AppStateToJson(this);
}
