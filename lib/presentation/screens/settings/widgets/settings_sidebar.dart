import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../common/nav_row.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'settings_tab.dart';

/// The settings screen's tab list, with the way back to the app.
class SettingsSidebar extends StatelessWidget {
  final SettingsTab activeTab;
  final ValueChanged<SettingsTab> onTabSelected;
  final VoidCallback onBack;

  const SettingsSidebar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Back button + Settings heading ────────────────
        // Only the arrow acts. The heading beside it names the panel you are
        // already in, and a title that navigates away when you touch it is
        // the same trap the server header used to be.
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            spacing: 11,
            children: [
              _BackButton(onTap: onBack),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Settings',
                      style: AppText.panelTitle.copyWith(
                        color: themeState.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Back to home',
                      style: AppText.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: themeState.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Inset rather than edge-to-edge: it separates the two halves of the
        // nav, it isn't the panel's own edge.
        Container(
          height: 1,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          color: themeState.borderPrimary,
        ),
        // The design's settings nav rows are the sidebar's rows — same
        // gradient, ring, padding and radius — so they use the same widget
        // rather than a fork that would drift.
        _tab(SettingsTab.appearance, Icons.palette_outlined, 'Appearance'),
        _tab(SettingsTab.general, Icons.tune_rounded, 'General'),
        _tab(
          SettingsTab.voiceAndAudio,
          Icons.headset_outlined,
          'Voice & audio',
        ),
        _tab(SettingsTab.backup, Icons.cloud_outlined, 'Cloud backup'),
      ],
    );
  }

  Widget _tab(SettingsTab tab, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: NavRow(
        icon: icon,
        label: label,
        isSelected: activeTab == tab,
        onTap: () => onTabSelected(tab),
      ),
    );
  }
}

/// The way out of settings: a tinted tile holding the back arrow.
///
/// It was a bare [Container] when the whole header row carried the tap. Now
/// that it is the only thing that navigates, it needs its own hit area, hover
/// and tooltip — the tile already looked like a button, so this is only making
/// it behave like the one it was pretending to be.
class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);

    return Tooltip(
      message: 'Back to home',
      waitDuration: K.tooltipDelay,
      child: Material(
        color: themeState.bgHover,
        borderRadius: radius,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          hoverColor: themeState.bgActive,
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 17,
              color: themeState.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
