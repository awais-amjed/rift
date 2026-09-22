part of 'app_cubit.dart';

/// See [AppCubit]. Grouped by what each field belongs to; everything here is
/// this device's choice alone.
@JsonSerializable(explicitToJson: true)
class AppState {
  // ── Persisted ──────────────────────────────────────────────
  /// Whether the left sidebar is shown. Hidden it takes no width at all and an
  /// [EdgeTab] brings it back — the same as the member list on the other side.
  /// It used to be `isPinned`, when hiding it meant swapping the panel for an
  /// overlay that slid out on hover.
  final bool sidebarOpen;
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

  /// Whether a watched stream shows the full stats card. Off by default: the
  /// quality badge beside the sharer's name covers what most people check.
  final bool showStreamStats;

  /// What to do with an image the on-device classifier flags. Per device,
  /// because the verdict is: the model runs on bytes only this device holds.
  final SensitiveContentMode sensitiveContentMode;

  /// Whether this device builds a preview for a link as it is typed. The
  /// fetch is made from here, by the sender, and nowhere else — so this is
  /// a choice about what this device reaches out to.
  final bool linkPreviewsEnabled;

  /// Whether the right-hand member sidebar is expanded. Persisted so the
  /// layout survives a restart.
  final bool membersSidebarOpen;

  /// Whether the docked member list is actually showing: the saved choice,
  /// unless a focused call tile has it out of the way.
  bool get membersSidebarShown => membersSidebarOpen && !membersHiddenForFocus;

  /// How wide the user has dragged the left sidebar. Stored raw and clamped
  /// on read by [SidebarSizing], because the window it was chosen in is not
  /// necessarily the window it will next be shown in.
  final double sidebarWidth;

  /// The member list's dragged width, stored raw for the same reason.
  final double membersSidebarWidth;
  final String? outputDeviceId;
  final String? inputDeviceId;

  // ── Audio processing (applied to the mic capture track) ────
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGainControl;

  // ── The soundboard, as this device hears it ───────────────
  // Both of these are the *listener's*, and neither asks a server anything.
  // A clip is played locally by everyone who receives the press, so what it
  // sounds like here is decided here — and per-person volume for a single
  // sound goes in [participantSettings] under
  // `ParticipantIdentity.soundboardSettingsKey`, beside the one for a voice
  // and the one for a shared track.

  /// Whether this device plays **other people's** clips at all. Never your
  /// own — see [SoundboardVolume] for why the two differ.
  final bool soundboardMuted;

  /// How loud, 0–1, when it does. Starts below the room: a clip is a
  /// punctuation mark and should not be louder than the person talking.
  final double soundboardVolume;

  /// Emoji the user reaches for, most recent first, capped at
  /// [AppCubit.maxRecentEmojis]. Kept here rather than in the emoji package's
  /// own store: its writer needs a handle to the widget it ships, which the
  /// app's own picker doesn't use.
  final List<String> recentEmojis;

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

  /// Whether the docked member list is out of the way for a focused call
  /// tile. Kept apart from [membersSidebarOpen] so leaving focus puts back
  /// whatever the user had, without anything remembering it.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool membersHiddenForFocus;

  /// A focused call has gone idle: one tile fills the stage and its controls
  /// have faded. With both side panels hidden too, the shell drops the
  /// gutter and the panel's corners so the stream runs to the window's edge.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool stageChromeHidden;

  /// The push-to-talk key as the desktop reports it ("Press F9"), while a
  /// desktop shortcut is bound — null otherwise. On Linux the desktop owns
  /// the key once it has asked the user, and re-binding with a different
  /// suggestion gets the old key back, so this, not [pushToTalkKeyLabel], is
  /// the key that actually works.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? desktopPushToTalkKey;

  /// Rift is waiting on the desktop for the push-to-talk key — binding, or
  /// the user looking at the desktop's dialog. Settings holds its controls
  /// until the answer arrives, because a key picked meanwhile is replaced by
  /// whatever the desktop says.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool desktopPushToTalkPending;

  const AppState({
    this.sidebarOpen = true,
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
    this.showStreamStats = false,
    this.sensitiveContentMode = SensitiveContentMode.blur,
    this.linkPreviewsEnabled = true,
    this.outputDeviceId,
    this.inputDeviceId,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.recentEmojis = const [],
    this.soundboardMuted = false,
    this.soundboardVolume = 0.6,
    this.membersSidebarOpen = true,
    this.sidebarWidth = K.sidebarWidth,
    this.membersSidebarWidth = K.membersSidebarWidth,
    this.isHovered = false,
    this.selectedChannelId,
    this.participants = const [],
    this.surface = HomeSurface.server,
    this.membersHiddenForFocus = false,
    this.stageChromeHidden = false,
    this.desktopPushToTalkKey,
    this.desktopPushToTalkPending = false,
  });

  AppState copyWith({
    bool? sidebarOpen,
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
    bool? showStreamStats,
    SensitiveContentMode? sensitiveContentMode,
    bool? linkPreviewsEnabled,
    String? outputDeviceId,
    bool clearOutputDeviceId = false,
    String? inputDeviceId,
    bool clearInputDeviceId = false,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? autoGainControl,
    List<String>? recentEmojis,
    bool? soundboardMuted,
    double? soundboardVolume,
    bool? membersSidebarOpen,
    double? sidebarWidth,
    double? membersSidebarWidth,
    bool? isHovered,
    String? selectedChannelId,
    bool clearSelectedChannelId = false,
    List<ParticipantInfo>? participants,
    HomeSurface? surface,
    bool? membersHiddenForFocus,
    bool? stageChromeHidden,
    String? desktopPushToTalkKey,
    bool clearDesktopPushToTalkKey = false,
    bool? desktopPushToTalkPending,
  }) {
    return AppState(
      sidebarOpen: sidebarOpen ?? this.sidebarOpen,
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
      showStreamStats: showStreamStats ?? this.showStreamStats,
      sensitiveContentMode: sensitiveContentMode ?? this.sensitiveContentMode,
      linkPreviewsEnabled: linkPreviewsEnabled ?? this.linkPreviewsEnabled,
      outputDeviceId: clearOutputDeviceId
          ? null
          : (outputDeviceId ?? this.outputDeviceId),
      inputDeviceId: clearInputDeviceId
          ? null
          : (inputDeviceId ?? this.inputDeviceId),
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      autoGainControl: autoGainControl ?? this.autoGainControl,
      recentEmojis: recentEmojis ?? this.recentEmojis,
      soundboardMuted: soundboardMuted ?? this.soundboardMuted,
      soundboardVolume: soundboardVolume ?? this.soundboardVolume,
      membersSidebarOpen: membersSidebarOpen ?? this.membersSidebarOpen,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      membersSidebarWidth: membersSidebarWidth ?? this.membersSidebarWidth,
      isHovered: isHovered ?? this.isHovered,
      selectedChannelId: clearSelectedChannelId
          ? null
          : (selectedChannelId ?? this.selectedChannelId),
      participants: participants ?? this.participants,
      surface: surface ?? this.surface,
      membersHiddenForFocus:
          membersHiddenForFocus ?? this.membersHiddenForFocus,
      stageChromeHidden: stageChromeHidden ?? this.stageChromeHidden,
      desktopPushToTalkKey: clearDesktopPushToTalkKey
          ? null
          : (desktopPushToTalkKey ?? this.desktopPushToTalkKey),
      desktopPushToTalkPending:
          desktopPushToTalkPending ?? this.desktopPushToTalkPending,
    );
  }

  factory AppState.fromJson(Map<String, dynamic> json) =>
      _$AppStateFromJson(json);

  Map<String, dynamic> toJson() => _$AppStateToJson(this);
}
