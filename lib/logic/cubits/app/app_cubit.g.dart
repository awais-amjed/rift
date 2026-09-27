// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_cubit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppState _$AppStateFromJson(Map<String, dynamic> json) => AppState(
  sidebarOpen: json['sidebarOpen'] as bool? ?? true,
  audioEnabled: json['audioEnabled'] as bool? ?? true,
  videoEnabled: json['videoEnabled'] as bool? ?? false,
  pushToTalkEnabled: json['pushToTalkEnabled'] as bool? ?? false,
  pushToTalkKeyId: (json['pushToTalkKeyId'] as num?)?.toInt(),
  pushToTalkKeyLabel: json['pushToTalkKeyLabel'] as String?,
  titleBarVisible: json['titleBarVisible'] as bool? ?? true,
  screenShareSettings: json['screenShareSettings'] == null
      ? const ScreenShareSettings()
      : ScreenShareSettings.fromJson(
          json['screenShareSettings'] as Map<String, dynamic>,
        ),
  participantSettings:
      (json['participantSettings'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, ParticipantSetting.fromJson(e as Map<String, dynamic>)),
      ) ??
      const {},
  windowWidth: (json['windowWidth'] as num?)?.toDouble(),
  windowHeight: (json['windowHeight'] as num?)?.toDouble(),
  windowX: (json['windowX'] as num?)?.toDouble(),
  windowY: (json['windowY'] as num?)?.toDouble(),
  disableAudioDucking: json['disableAudioDucking'] as bool? ?? false,
  askBeforeVoiceSwitch: json['askBeforeVoiceSwitch'] as bool? ?? true,
  verifiedCodes:
      (json['verifiedCodes'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  statsOverlayPinned: json['statsOverlayPinned'] as bool? ?? false,
  showStreamStats: json['showStreamStats'] as bool? ?? false,
  sensitiveContentMode:
      $enumDecodeNullable(
        _$SensitiveContentModeEnumMap,
        json['sensitiveContentMode'],
      ) ??
      SensitiveContentMode.blur,
  linkPreviewsEnabled: json['linkPreviewsEnabled'] as bool? ?? true,
  outputDeviceId: json['outputDeviceId'] as String?,
  inputDeviceId: json['inputDeviceId'] as String?,
  noiseSuppression: json['noiseSuppression'] as bool? ?? true,
  echoCancellation: json['echoCancellation'] as bool? ?? true,
  autoGainControl: json['autoGainControl'] as bool? ?? true,
  recentEmojis:
      (json['recentEmojis'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  soundboardMuted: json['soundboardMuted'] as bool? ?? false,
  soundboardVolume: (json['soundboardVolume'] as num?)?.toDouble() ?? 0.6,
  appSounds:
      (json['appSounds'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, ParticipantSetting.fromJson(e as Map<String, dynamic>)),
      ) ??
      const {},
  membersSidebarOpen: json['membersSidebarOpen'] as bool? ?? true,
  sidebarWidth: (json['sidebarWidth'] as num?)?.toDouble() ?? K.sidebarWidth,
  membersSidebarWidth:
      (json['membersSidebarWidth'] as num?)?.toDouble() ??
      K.membersSidebarWidth,
  dmCallStageShare:
      (json['dmCallStageShare'] as num?)?.toDouble() ?? K.dmCallStageShare,
);

Map<String, dynamic> _$AppStateToJson(AppState instance) => <String, dynamic>{
  'sidebarOpen': instance.sidebarOpen,
  'audioEnabled': instance.audioEnabled,
  'videoEnabled': instance.videoEnabled,
  'pushToTalkEnabled': instance.pushToTalkEnabled,
  'pushToTalkKeyId': instance.pushToTalkKeyId,
  'pushToTalkKeyLabel': instance.pushToTalkKeyLabel,
  'titleBarVisible': instance.titleBarVisible,
  'screenShareSettings': instance.screenShareSettings.toJson(),
  'participantSettings': instance.participantSettings.map(
    (k, e) => MapEntry(k, e.toJson()),
  ),
  'windowWidth': instance.windowWidth,
  'windowHeight': instance.windowHeight,
  'windowX': instance.windowX,
  'windowY': instance.windowY,
  'disableAudioDucking': instance.disableAudioDucking,
  'askBeforeVoiceSwitch': instance.askBeforeVoiceSwitch,
  'statsOverlayPinned': instance.statsOverlayPinned,
  'showStreamStats': instance.showStreamStats,
  'sensitiveContentMode':
      _$SensitiveContentModeEnumMap[instance.sensitiveContentMode]!,
  'linkPreviewsEnabled': instance.linkPreviewsEnabled,
  'membersSidebarOpen': instance.membersSidebarOpen,
  'sidebarWidth': instance.sidebarWidth,
  'membersSidebarWidth': instance.membersSidebarWidth,
  'dmCallStageShare': instance.dmCallStageShare,
  'outputDeviceId': instance.outputDeviceId,
  'inputDeviceId': instance.inputDeviceId,
  'noiseSuppression': instance.noiseSuppression,
  'echoCancellation': instance.echoCancellation,
  'autoGainControl': instance.autoGainControl,
  'soundboardMuted': instance.soundboardMuted,
  'soundboardVolume': instance.soundboardVolume,
  'appSounds': instance.appSounds.map((k, e) => MapEntry(k, e.toJson())),
  'verifiedCodes': instance.verifiedCodes,
  'recentEmojis': instance.recentEmojis,
};

const _$SensitiveContentModeEnumMap = {
  SensitiveContentMode.off: 'off',
  SensitiveContentMode.blur: 'blur',
  SensitiveContentMode.hide: 'hide',
};
