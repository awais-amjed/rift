// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_cubit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThemeState _$ThemeStateFromJson(Map<String, dynamic> json) => ThemeState(
  themeMode:
      $enumDecodeNullable(_$ThemeModeEnumMap, json['themeMode']) ??
      ThemeMode.dark,
  paletteId: json['paletteId'] as String? ?? 'indigo',
);

Map<String, dynamic> _$ThemeStateToJson(ThemeState instance) =>
    <String, dynamic>{
      'themeMode': _$ThemeModeEnumMap[instance.themeMode]!,
      'paletteId': instance.paletteId,
    };

const _$ThemeModeEnumMap = {
  ThemeMode.system: 'system',
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
};
