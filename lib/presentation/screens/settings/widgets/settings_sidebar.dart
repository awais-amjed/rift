import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/nav_row.dart';
import '../../../theme/app_text.dart';
import 'reset_vault_card.dart';
import 'settings_tab.dart';

class SettingsSidebar extends StatelessWidget {
  final SettingsTab activeTab;
  final ValueChanged<SettingsTab> onTabSelected;
  final ThemeState themeState;
  final VoidCallback onBack;

  /// Wipes the vault. Lives at the bottom of the nav rather than in a footer
  /// under the content, where it sat next to whatever tab you had open.
  final VoidCallback onResetVault;

  const SettingsSidebar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    required this.themeState,
    required this.onBack,
    required this.onResetVault,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Back button + Settings heading ────────────────
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onBack,
            hoverColor: themeState.bgHover,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                spacing: 11,
                children: [
                  // The arrow gets its own tile so the row reads as a control
                  // and lines up with the server header it replaces.
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: themeState.bgHover,
                      borderRadius: BorderRadius.circular(K.radiusRow),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 17,
                      color: themeState.textSecondary,
                    ),
                  ),
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
        _tab(
          SettingsTab.voiceAndAudio,
          Icons.headset_outlined,
          'Voice & Audio',
        ),
        _tab(SettingsTab.backup, Icons.cloud_outlined, 'Cloud Backup'),
        const Spacer(),
        ResetVaultCard(themeState: themeState, onTap: onResetVault),
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
