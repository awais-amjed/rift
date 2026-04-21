import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'settings_tab.dart';

class SettingsSidebar extends StatelessWidget {
  final SettingsTab activeTab;
  final ValueChanged<SettingsTab> onTabSelected;
  final ThemeState themeState;

  const SettingsSidebar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: themeState.textTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: themeState.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
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
        ],
      ),
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
                  style: TextStyle(
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

