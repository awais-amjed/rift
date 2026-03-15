// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_cubit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppState _$AppStateFromJson(Map<String, dynamic> json) => AppState(
  isPinned: json['isPinned'] as bool? ?? true,
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
);

Map<String, dynamic> _$AppStateToJson(AppState instance) => <String, dynamic>{
  'isPinned': instance.isPinned,
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
};
