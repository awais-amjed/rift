import 'package:flutter/material.dart';

/// One brightness mode's worth of palette colors.
///
/// Widgets never read these directly — they go through the semantic getters
/// on `ThemeState`, which pick the right mode.
class PaletteColors {
  // Accent
  final Color primary;
  final Color onPrimary;

  /// Second stop for identity gradients (server icons, avatars).
  final Color gradientPartner;

  // Backgrounds
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgTertiary;
  final Color bgHover;
  final Color bgActive;

  /// Elevated overlay surfaces (popovers, context menus, floating bars).
  final Color bgElevated;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textQuaternary;

  // Chrome
  final Color border;
  final Color sidebarBg;

  // Accent-derived active states (selected channel, selected cards)
  final Color channelActiveBg;
  final Color channelActiveText;
  final Color channelActiveBorder;

  const PaletteColors({
    required this.primary,
    required this.onPrimary,
    required this.gradientPartner,
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.bgHover,
    required this.bgActive,
    required this.bgElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textQuaternary,
    required this.border,
    required this.sidebarBg,
    required this.channelActiveBg,
    required this.channelActiveText,
    required this.channelActiveBorder,
  });
}

/// A user-selectable color palette: accent + neutrals for both modes.
///
/// Semantic status colors (success/warning/error, speaking-green,
/// muted-rose) are shared across palettes and live in `CustomColors` —
/// they must never be repurposed as accents (AGENTS.md).
class AppPalette {
  final String id;
  final String name;
  final String description;
  final PaletteColors dark;
  final PaletteColors light;

  const AppPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.dark,
    required this.light,
  });

  static const List<AppPalette> all = [indigo, abyss, ember, mono];

  static AppPalette byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => indigo);

  // ── Indigo (default) — indigo-500 on zinc ─────────────────────────────────
  static const indigo = AppPalette(
    id: 'indigo',
    name: 'Indigo',
    description: 'The classic Rift look',
    dark: PaletteColors(
      primary: Color(0xFF6366F1),
      onPrimary: Colors.white,
      gradientPartner: Color(0xFFEC4899),
      bgPrimary: Color(0xFF09090B),
      bgSecondary: Color(0xFF121214),
      bgTertiary: Color(0xFF18181B),
      bgHover: Color(0x0DFFFFFF),
      bgActive: Color(0x1AFFFFFF),
      bgElevated: Color(0xFF1E1E21),
      textPrimary: Color(0xFFFAFAFA),
      textSecondary: Color(0xFFE4E4E7),
      textTertiary: Color(0xFFA1A1AA),
      textQuaternary: Color(0xFF71717A),
      border: Color(0x0DFFFFFF),
      sidebarBg: Color(0xF2121214),
      channelActiveBg: Color(0x1A6366F1),
      channelActiveText: Color(0xFFE0E7FF),
      channelActiveBorder: Color(0x336366F1),
    ),
    light: PaletteColors(
      primary: Color(0xFF6366F1),
      onPrimary: Colors.white,
      gradientPartner: Color(0xFFEC4899),
      bgPrimary: Color(0xFFFAFAFA),
      bgSecondary: Color(0xFFFFFFFF),
      bgTertiary: Color(0xFFF4F4F5),
      bgHover: Color(0xFFF4F4F5),
      bgActive: Color(0xFFE4E4E7),
      bgElevated: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF18181B),
      textSecondary: Color(0xFF3F3F46),
      textTertiary: Color(0xFF71717A),
      textQuaternary: Color(0xFFA1A1AA),
      border: Color(0xFFE4E4E7),
      sidebarBg: Color(0xF2FFFFFF),
      channelActiveBg: Color(0xFFEEF2FF),
      channelActiveText: Color(0xFF4338CA),
      channelActiveBorder: Color(0xFFE0E7FF),
    ),
  );

  // ── Abyss — teal on blue-black ─────────────────────────────────────────────
  static const abyss = AppPalette(
    id: 'abyss',
    name: 'Abyss',
    description: 'Cold teal out of a blue-black chasm',
    dark: PaletteColors(
      primary: Color(0xFF2DD4BF),
      onPrimary: Color(0xFF06211E),
      gradientPartner: Color(0xFF38BDF8),
      bgPrimary: Color(0xFF070B0F),
      bgSecondary: Color(0xFF0C1218),
      bgTertiary: Color(0xFF121A21),
      bgHover: Color(0x1494C5DE),
      bgActive: Color(0x2294C5DE),
      bgElevated: Color(0xFF16202A),
      textPrimary: Color(0xFFEEF6F9),
      textSecondary: Color(0xFFC9D9E1),
      textTertiary: Color(0xFF93A8B4),
      textQuaternary: Color(0xFF56707E),
      border: Color(0x1794C5DE),
      sidebarBg: Color(0xF20C1218),
      channelActiveBg: Color(0x1C2DD4BF),
      channelActiveText: Color(0xFFA7F3EA),
      channelActiveBorder: Color(0x3D2DD4BF),
    ),
    light: PaletteColors(
      primary: Color(0xFF0D9488),
      onPrimary: Colors.white,
      gradientPartner: Color(0xFF0284C7),
      bgPrimary: Color(0xFFF4F8F9),
      bgSecondary: Color(0xFFFFFFFF),
      bgTertiary: Color(0xFFEDF3F5),
      bgHover: Color(0xFFEDF3F5),
      bgActive: Color(0xFFDCE7EA),
      bgElevated: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF0F1E26),
      textSecondary: Color(0xFF31474F),
      textTertiary: Color(0xFF47606C),
      textQuaternary: Color(0xFF8AA2AC),
      border: Color(0xFFDCE7EA),
      sidebarBg: Color(0xF2FFFFFF),
      channelActiveBg: Color(0xFFE4F7F4),
      channelActiveText: Color(0xFF0F766E),
      channelActiveBorder: Color(0xFFBFEAE4),
    ),
  );

  // ── Ember — copper on warm graphite ────────────────────────────────────────
  static const ember = AppPalette(
    id: 'ember',
    name: 'Ember',
    description: 'Copper warmth for late-night calls',
    dark: PaletteColors(
      primary: Color(0xFFFB923C),
      onPrimary: Color(0xFF2A1204),
      gradientPartner: Color(0xFFF43F5E),
      bgPrimary: Color(0xFF0C0A09),
      bgSecondary: Color(0xFF151210),
      bgTertiary: Color(0xFF1B1815),
      bgHover: Color(0x12FFD5AA),
      bgActive: Color(0x1FFFD5AA),
      bgElevated: Color(0xFF201B17),
      textPrimary: Color(0xFFFAF6F2),
      textSecondary: Color(0xFFE0DAD4),
      textTertiary: Color(0xFFA8A29E),
      textQuaternary: Color(0xFF78716C),
      border: Color(0x14FFD5AA),
      sidebarBg: Color(0xF2151210),
      channelActiveBg: Color(0x1CFB923C),
      channelActiveText: Color(0xFFFED7AA),
      channelActiveBorder: Color(0x3DFB923C),
    ),
    light: PaletteColors(
      primary: Color(0xFFEA580C),
      onPrimary: Colors.white,
      gradientPartner: Color(0xFFE11D48),
      bgPrimary: Color(0xFFFAF8F6),
      bgSecondary: Color(0xFFFFFFFF),
      bgTertiary: Color(0xFFF4F0EC),
      bgHover: Color(0xFFF4F0EC),
      bgActive: Color(0xFFE8E1DA),
      bgElevated: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF211C18),
      textSecondary: Color(0xFF443E38),
      textTertiary: Color(0xFF5B544E),
      textQuaternary: Color(0xFFA49C94),
      border: Color(0xFFE8E1DA),
      sidebarBg: Color(0xF2FFFFFF),
      channelActiveBg: Color(0xFFFDEEE2),
      channelActiveText: Color(0xFFC2410C),
      channelActiveBorder: Color(0xFFF9DCC4),
    ),
  );

  // ── Mono — grayscale, inverted accents ─────────────────────────────────────
  static const mono = AppPalette(
    id: 'mono',
    name: 'Mono',
    description: 'No accent hue — people are the color',
    dark: PaletteColors(
      primary: Color(0xFFFAFAFA),
      onPrimary: Color(0xFF0A0A0A),
      gradientPartner: Color(0xFFA3A3A3),
      bgPrimary: Color(0xFF0A0A0A),
      bgSecondary: Color(0xFF141414),
      bgTertiary: Color(0xFF1A1A1A),
      bgHover: Color(0x0DFFFFFF),
      bgActive: Color(0x1AFFFFFF),
      bgElevated: Color(0xFF1F1F1F),
      textPrimary: Color(0xFFFAFAFA),
      textSecondary: Color(0xFFE5E5E5),
      textTertiary: Color(0xFFA3A3A3),
      textQuaternary: Color(0xFF737373),
      border: Color(0x12FFFFFF),
      sidebarBg: Color(0xF2141414),
      channelActiveBg: Color(0x17FFFFFF),
      channelActiveText: Color(0xFFFAFAFA),
      channelActiveBorder: Color(0x2EFFFFFF),
    ),
    light: PaletteColors(
      primary: Color(0xFF171717),
      onPrimary: Color(0xFFFAFAFA),
      gradientPartner: Color(0xFF525252),
      bgPrimary: Color(0xFFF7F7F7),
      bgSecondary: Color(0xFFFFFFFF),
      bgTertiary: Color(0xFFF0F0F0),
      bgHover: Color(0xFFF0F0F0),
      bgActive: Color(0xFFE5E5E5),
      bgElevated: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF171717),
      textSecondary: Color(0xFF404040),
      textTertiary: Color(0xFF525252),
      textQuaternary: Color(0xFFA3A3A3),
      border: Color(0xFFE5E5E5),
      sidebarBg: Color(0xF2FFFFFF),
      channelActiveBg: Color(0xFFEDEDED),
      channelActiveText: Color(0xFF171717),
      channelActiveBorder: Color(0xFFD4D4D4),
    ),
  );
}
