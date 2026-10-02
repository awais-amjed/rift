part of 'app_cubit.dart';

/// See [AppCubit]. Grouped by what each field belongs to; everything here is
/// this device's choice alone.
@JsonSerializable(explicitToJson: true)
class AppState {
  // ── Persisted ──────────────────────────────────────────────
  /// Whether the left sidebar is shown. Hidden it takes no width at all and a
  /// button at the start of the pane's header brings it back — the member
  /// list has the same at the other end.
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

  /// Whether clicking another voice channel while in a call asks first. On
  /// by default: one click used to drop the call and join the next room, and
  /// the people left behind hear you leave whether or not you meant to.
  final bool askBeforeVoiceSwitch;
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

  /// How much of a DM conversation's height its call takes, as the user last
  /// dragged it. Stored raw and clamped on read (`DmCallStage`), like the
  /// widths above.
  final double dmCallStageShare;
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

  // ── Rift's own sounds, as this device hears them ──────────
  /// Mute and volume for each [AppSound], keyed by its name. Absent
  /// until somebody moves one, so [AppSound.settingIn] supplies the default.
  final Map<String, ParticipantSetting> appSounds;

  // ── People whose keys you have checked ────────────────────
  /// The safety code you saw when you marked somebody verified, under
  /// `<tier>:<their id>` — see `SafetyCode`. Kept rather than a bare flag, so
  /// a key that changes afterwards no longer matches and the profile can say
  /// so instead of going on claiming they are verified.
  ///
  /// This device's belief and nobody else's: it is not uploaded, and another
  /// device of yours has to check for itself.
  final Map<String, String> verifiedCodes;

  /// The chat key last seen for each person, under the same
  /// `<tier>:<their id>` — see [SeenKey]. What says a key changed for
  /// somebody nobody verified, which is almost everybody.
  final Map<String, SeenKey> seenKeys;

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

  /// A DM call has been given the whole conversation pane: the conversation
  /// list folds away and the messages move to a side panel. For one call
  /// only — hanging up puts the split back.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool dmCallExpanded;

  /// Whether an expanded DM call has its messages open beside it.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool dmCallChatOpen;

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
    this.askBeforeVoiceSwitch = true,
    this.verifiedCodes = const {},
    this.seenKeys = const {},
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
    this.appSounds = const {},
    this.membersSidebarOpen = true,
    this.sidebarWidth = K.sidebarWidth,
    this.membersSidebarWidth = K.membersSidebarWidth,
    this.dmCallStageShare = K.dmCallStageShare,
    this.isHovered = false,
    this.selectedChannelId,
    this.participants = const [],
    this.surface = HomeSurface.server,
    this.membersHiddenForFocus = false,
    this.stageChromeHidden = false,
    this.dmCallExpanded = false,
    this.dmCallChatOpen = true,
    this.desktopPushToTalkKey,
    this.desktopPushToTalkPending = false,
  });

  /// Somebody you verified now has a key you have not checked. Sending is
  /// held until you do: you said this key was theirs, and a server that
  /// swapped it would be reading whatever you send next. Comparing the new
  /// code or forgetting the old one both clear it, as both acknowledge.
  bool keyChangedSinceVerified(String person) =>
      verifiedCodes.containsKey(person) &&
      (seenKeys[person]?.unacknowledgedChange ?? false);

  /// Everybody [keyChangedSinceVerified] holds.
  Set<String> get keysToCheck => {
    for (final person in verifiedCodes.keys)
      if (keyChangedSinceVerified(person)) person,
  };

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
    bool? askBeforeVoiceSwitch,
    Map<String, String>? verifiedCodes,
    Map<String, SeenKey>? seenKeys,
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
    Map<String, ParticipantSetting>? appSounds,
    bool? membersSidebarOpen,
    double? sidebarWidth,
    double? membersSidebarWidth,
    double? dmCallStageShare,
    bool? isHovered,
    String? selectedChannelId,
    bool clearSelectedChannelId = false,
    List<ParticipantInfo>? participants,
    HomeSurface? surface,
    bool? membersHiddenForFocus,
    bool? stageChromeHidden,
    bool? dmCallExpanded,
    bool? dmCallChatOpen,
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
      askBeforeVoiceSwitch: askBeforeVoiceSwitch ?? this.askBeforeVoiceSwitch,
      verifiedCodes: verifiedCodes ?? this.verifiedCodes,
      seenKeys: seenKeys ?? this.seenKeys,
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
      appSounds: appSounds ?? this.appSounds,
      membersSidebarOpen: membersSidebarOpen ?? this.membersSidebarOpen,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      membersSidebarWidth: membersSidebarWidth ?? this.membersSidebarWidth,
      dmCallStageShare: dmCallStageShare ?? this.dmCallStageShare,
      isHovered: isHovered ?? this.isHovered,
      selectedChannelId: clearSelectedChannelId
          ? null
          : (selectedChannelId ?? this.selectedChannelId),
      participants: participants ?? this.participants,
      surface: surface ?? this.surface,
      membersHiddenForFocus:
          membersHiddenForFocus ?? this.membersHiddenForFocus,
      stageChromeHidden: stageChromeHidden ?? this.stageChromeHidden,
      dmCallExpanded: dmCallExpanded ?? this.dmCallExpanded,
      dmCallChatOpen: dmCallChatOpen ?? this.dmCallChatOpen,
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
