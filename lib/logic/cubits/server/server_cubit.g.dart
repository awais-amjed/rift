// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_cubit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ServerState _$ServerStateFromJson(Map<String, dynamic> json) => ServerState(
  servers:
      (json['servers'] as List<dynamic>?)
          ?.map((e) => Server.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  selectedServerId: json['selectedServerId'] as String?,
);

Map<String, dynamic> _$ServerStateToJson(ServerState instance) =>
    <String, dynamic>{
      'servers': instance.servers.map((e) => e.toJson()).toList(),
      'selectedServerId': instance.selectedServerId,
    };
