// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_cubit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppState _$AppStateFromJson(Map<String, dynamic> json) => AppState(
  isPinned: json['isPinned'] as bool? ?? true,
  audioEnabled: json['audioEnabled'] as bool? ?? true,
  videoEnabled: json['videoEnabled'] as bool? ?? false,
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
);

Map<String, dynamic> _$AppStateToJson(AppState instance) => <String, dynamic>{
  'isPinned': instance.isPinned,
  'audioEnabled': instance.audioEnabled,
  'videoEnabled': instance.videoEnabled,
  'screenShareSettings': instance.screenShareSettings.toJson(),
  'participantSettings': instance.participantSettings.map(
    (k, e) => MapEntry(k, e.toJson()),
  ),
};
