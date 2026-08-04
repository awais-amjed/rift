import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
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
        SidebarItem(
          icon: Icons.palette_outlined,
          label: 'Appearance',
          isActive: activeTab == SettingsTab.appearance,
          themeState: themeState,
          onTap: () => onTabSelected(SettingsTab.appearance),
        ),
        SidebarItem(
          icon: Icons.headset_outlined,
          label: 'Voice & Audio',
          isActive: activeTab == SettingsTab.voiceAndAudio,
          themeState: themeState,
          onTap: () => onTabSelected(SettingsTab.voiceAndAudio),
        ),
        SidebarItem(
          icon: Icons.cloud_outlined,
          label: 'Cloud Backup',
          isActive: activeTab == SettingsTab.backup,
          themeState: themeState,
          onTap: () => onTabSelected(SettingsTab.backup),
        ),
        const Spacer(),
        ResetVaultCard(themeState: themeState, onTap: onResetVault),
      ],
    );
  }
}

class SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final ThemeState themeState;
  final VoidCallback onTap;

  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = themeState.channelActiveText;
    final activeBg = themeState.channelActiveBg;
    final textColor = isActive ? activeColor : themeState.textSecondary;
    final bgColor = isActive ? activeBg : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 17, color: textColor),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: AppText.row.copyWith(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
