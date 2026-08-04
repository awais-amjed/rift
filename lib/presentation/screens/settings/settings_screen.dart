import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../common/app_panel.dart';
import '../../common/canvas_backdrop.dart';
import '../../common/confirm_dialog.dart';
import '../../common/icon_tile.dart';
import '../../theme/app_text.dart';
import 'widgets/appearance_content.dart';
import 'widgets/backup_content/backup_content.dart';
import 'widgets/settings_sidebar.dart';
import 'widgets/settings_tab.dart';
import 'widgets/voice_audio_content.dart';

export 'widgets/appearance_content.dart';
export 'widgets/backup_content/backup_content.dart';
export 'widgets/settings_sidebar.dart';
export 'widgets/settings_tab.dart';
export 'widgets/voice_audio_content.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsTab _activeTab = SettingsTab.appearance;

  String get _tabTitle => switch (_activeTab) {
    SettingsTab.appearance => 'Appearance',
    SettingsTab.voiceAndAudio => 'Voice & Audio',
    SettingsTab.backup => 'Cloud Backup',
  };

  String get _tabSubtitle => switch (_activeTab) {
    SettingsTab.appearance => 'Customize the look of the app.',
    SettingsTab.voiceAndAudio => 'Configure voice input behavior.',
    SettingsTab.backup => 'Save or restore your vault backup.',
  };

  IconData get _tabIcon => switch (_activeTab) {
    SettingsTab.appearance => Icons.palette_outlined,
    SettingsTab.voiceAndAudio => Icons.headset_outlined,
    SettingsTab.backup => Icons.cloud_outlined,
  };

  /// Wipes the vault and server list from this device and returns to
  /// onboarding. Irreversible without a cloud or file backup.
  Future<void> _resetVault() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Reset Vault?',
      message:
          'This wipes all keys and saved servers from this device and returns '
          'you to onboarding. If you have no cloud backup, your identity will '
          'be permanently lost.',
      confirmLabel: 'Reset',
      icon: Icons.delete_forever,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await context.read<ServerCubit>().reset();
    if (!mounted) return;
    context.read<VaultCubit>().resetVault();
  }

  Widget _buildHeader(ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      child: Row(
        spacing: 12,
        children: [
          // The tab's own mark, so the content panel says which section you
          // are in as loudly as the nav row you clicked to get here.
          IconTile(
            icon: _tabIcon,
            color: themeState.accentBright,
            size: 36,
            radius: K.radiusButton,
            iconSize: 19,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tabTitle,
                  style: AppText.sectionTitle.copyWith(
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _tabSubtitle,
                  style: AppText.secondary.copyWith(
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Scaffold(
          body: BlocBuilder<AppCubit, AppState>(
            buildWhen: (prev, curr) =>
                prev.titleBarVisible != curr.titleBarVisible,
            builder: (context, appState) {
              final topOffset = kIsWeb
                  ? 0.0
                  : (appState.titleBarVisible ? K.titleBarHeight : 0.0);
              return CanvasBackdrop(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    K.panelGutter,
                    topOffset == 0 ? K.panelGutter : topOffset,
                    K.panelGutter,
                    K.panelGutter,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Left nav panel ───────────────────────────
                      AppPanel(
                        width: K.settingsNavWidth,
                        child: SettingsSidebar(
                          activeTab: _activeTab,
                          onTabSelected: (tab) =>
                              setState(() => _activeTab = tab),
                          themeState: themeState,
                          onBack: () => context.pop(),
                          onResetVault: _resetVault,
                        ),
                      ),
                      const SizedBox(width: K.panelGutter),
                      // ── Right content panel ──────────────────────
                      Expanded(
                        child: AppPanel(
                          color: themeState.bgContent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(themeState),
                              Divider(
                                height: 1,
                                color: themeState.borderPrimary,
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: switch (_activeTab) {
                                    SettingsTab.appearance => AppearanceContent(
                                      themeState: themeState,
                                    ),
                                    SettingsTab.voiceAndAudio =>
                                      VoiceAudioContent(themeState: themeState),
                                    SettingsTab.backup => BackupContent(
                                      themeState: themeState,
                                    ),
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
