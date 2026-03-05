part of 'theme_cubit.dart';

@JsonSerializable()
class ThemeState {
  final ThemeMode themeMode;

  ThemeState({this.themeMode = ThemeMode.dark});

  ThemeState copyWith({ThemeMode? themeMode}) {
    return ThemeState(themeMode: themeMode ?? this.themeMode);
  }

  bool get isLightTheme => themeMode == ThemeMode.light;

  bool get isDarkTheme => themeMode == ThemeMode.dark;

  factory ThemeState.fromJson(Map<String, dynamic> json) =>
      _$ThemeStateFromJson(json);

  Map<String, dynamic> toJson() => _$ThemeStateToJson(this);
}
