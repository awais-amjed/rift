part of 'theme_cubit.dart';

@JsonSerializable()
class ThemeState {
  final ThemeMode themeMode;

  /// Id of the active [AppPalette]. Unknown ids fall back to indigo.
  @JsonKey(defaultValue: 'indigo')
  final String paletteId;

  ThemeState({this.themeMode = ThemeMode.dark, this.paletteId = 'indigo'});

  ThemeState copyWith({ThemeMode? themeMode, String? paletteId}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      paletteId: paletteId ?? this.paletteId,
    );
  }

  bool get isLightTheme => themeMode == ThemeMode.light;

  bool get isDarkTheme => themeMode == ThemeMode.dark;

  AppPalette get palette => AppPalette.byId(paletteId);

  /// The active palette's colors for the current brightness.
  PaletteColors get colors => isDarkTheme ? palette.dark : palette.light;

  // ── Semantic color getters — the only color source for widgets ───

  // Accent
  Color get primary => colors.primary;

  Color get onPrimary => colors.onPrimary;

  /// Accent tuned for text and icons — [primary] is too dim at label sizes.
  Color get accentBright => colors.accentBright;

  Color get gradientPartner => colors.gradientPartner;

  /// Primary buttons and the composer's send control.
  LinearGradient get actionGradient => colors.actionGradient;

  /// Server icons and the local user's avatar.
  LinearGradient get identityGradient => colors.identityGradient;

  // Backgrounds — see PaletteColors for what each rung of the ladder is for.
  Color get bgPrimary => colors.bgPrimary;

  Color get bgContent => colors.bgContent;

  Color get bgSecondary => colors.bgSecondary;

  Color get bgTertiary => colors.bgTertiary;

  Color get bgHover => colors.bgHover;

  /// Half of [bgHover]. See `PaletteColors.bgHoverSubtle`.
  Color get bgHoverSubtle => colors.bgHoverSubtle;

  Color get bgActive => colors.bgActive;

  Color get bgElevated => colors.bgElevated;

  Color get railStrip => colors.railStrip;

  // Text colors
  Color get textPrimary => colors.textPrimary;

  Color get textSecondary => colors.textSecondary;

  Color get textTertiary => colors.textTertiary;

  Color get textQuaternary => colors.textQuaternary;

  // Borders
  Color get borderPrimary => colors.border;

  /// For surfaces floating over content, which need more edge than
  /// [borderPrimary] gives them against the canvas.
  Color get borderElevated => colors.borderElevated;

  // Channel active colors
  Color get channelActiveBg => colors.channelActiveBg;

  Color get channelActiveText => colors.channelActiveText;

  Color get channelActiveBorder => colors.channelActiveBorder;

  // Sidebar
  Color get sidebarBg => colors.sidebarBg;

  factory ThemeState.fromJson(Map<String, dynamic> json) =>
      _$ThemeStateFromJson(json);

  Map<String, dynamic> toJson() => _$ThemeStateToJson(this);
}
