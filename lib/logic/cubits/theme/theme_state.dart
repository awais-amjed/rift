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

  // ── Commonly used colors ──────────────────────────────────────

  // Backgrounds
  Color get bgPrimary =>
      isDarkTheme ? CustomColors.bgPrimaryDark : CustomColors.bgPrimaryLight;

  Color get bgSecondary => isDarkTheme
      ? CustomColors.bgSecondaryDark
      : CustomColors.bgSecondaryLight;

  Color get bgTertiary =>
      isDarkTheme ? CustomColors.bgTertiaryDark : CustomColors.bgTertiaryLight;

  Color get bgHover =>
      isDarkTheme ? CustomColors.bgHoverDark : CustomColors.bgHoverLight;

  Color get bgActive =>
      isDarkTheme ? CustomColors.bgActiveDark : CustomColors.bgActiveLight;

  // Text colors
  Color get textPrimary => isDarkTheme
      ? CustomColors.textPrimaryDark
      : CustomColors.textPrimaryLight;

  Color get textSecondary => isDarkTheme
      ? CustomColors.textSecondaryDark
      : CustomColors.textSecondaryLight;

  Color get textTertiary => isDarkTheme
      ? CustomColors.textTertiaryDark
      : CustomColors.textTertiaryLight;

  Color get textQuaternary => isDarkTheme
      ? CustomColors.textQuaternaryDark
      : CustomColors.textQuaternaryLight;

  // Borders
  Color get borderPrimary => isDarkTheme
      ? CustomColors.borderPrimaryDark
      : CustomColors.borderPrimaryLight;

  // Channel active colors
  Color get channelActiveBg => isDarkTheme
      ? CustomColors.channelActiveBgDark
      : CustomColors.channelActiveBgLight;

  Color get channelActiveText => isDarkTheme
      ? CustomColors.channelActiveTextDark
      : CustomColors.channelActiveTextLight;

  Color get channelActiveBorder => isDarkTheme
      ? CustomColors.channelActiveBorderDark
      : CustomColors.channelActiveBorderLight;

  // Sidebar
  Color get sidebarBg =>
      isDarkTheme ? CustomColors.sidebarBgDark : CustomColors.sidebarBgLight;

  factory ThemeState.fromJson(Map<String, dynamic> json) =>
      _$ThemeStateFromJson(json);

  Map<String, dynamic> toJson() => _$ThemeStateToJson(this);
}
