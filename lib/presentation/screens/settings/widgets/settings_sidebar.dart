import 'package:flutter/material.dart';

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
        InkWell(
          onTap: onBack,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: themeState.textPrimary,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: AppText.sectionTitle.copyWith(
                        fontSize: 17,
                        color: themeState.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Back to home',
                      style: AppText.secondary.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: themeState.borderPrimary),
        const SizedBox(height: 8),
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
