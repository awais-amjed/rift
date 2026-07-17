import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Scaffold(
          backgroundColor: themeState.bgSecondary,
          body: BlocBuilder<AppCubit, AppState>(
            buildWhen: (prev, curr) =>
                prev.titleBarVisible != curr.titleBarVisible,
            builder: (context, appState) {
              final topOffset = kIsWeb
                  ? 0.0
                  : (appState.titleBarVisible ? K.titleBarHeight : 0.0);
              return Padding(
                padding: EdgeInsets.only(top: topOffset),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Left sidebar ─────────────────────────────
                    SettingsSidebar(
                      activeTab: _activeTab,
                      onTabSelected: (tab) =>
                          setState(() => _activeTab = tab),
                      themeState: themeState,
                      onBack: () => context.pop(),
                    ),
                    VerticalDivider(
                        width: 1, color: themeState.borderPrimary),
                    // ── Right content area ───────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(24, 20, 16, 16),
                            child: Row(
                              children: [
                                Icon(
                                  _tabIcon,
                                  size: 20,
                                  color: themeState.textPrimary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _tabTitle,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: themeState.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _tabSubtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: themeState.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                              height: 1, color: themeState.borderPrimary),
                          // Content
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: switch (_activeTab) {
                                SettingsTab.appearance => AppearanceContent(
                                    themeState: themeState,
                                  ),
                                SettingsTab.voiceAndAudio =>
                                  VoiceAudioContent(
                                    themeState: themeState,
                                  ),
                                SettingsTab.backup => BackupContent(
                                    themeState: themeState,
                                  ),
                              },
                            ),
                          ),
                          // Footer
                          Divider(
                              height: 1, color: themeState.borderPrimary),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 12, 20, 16),
                            child: Row(
                              children: [
                                if (kDebugMode)
                                  TextButton.icon(
                                    onPressed: () async {
                                      final confirmed =
                                          await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title:
                                              const Text('Reset Vault?'),
                                          content: const Text(
                                            'This will wipe all keys and saved servers from secure storage. '
                                            'You will be sent back to onboarding.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx)
                                                      .pop(false),
                                              child:
                                                  const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx)
                                                      .pop(true),
                                              child: const Text(
                                                'Reset',
                                                style: TextStyle(
                                                    color: Colors.red),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true &&
                                          context.mounted) {
                                        await context
                                            .read<ServerCubit>()
                                            .reset();
                                        context
                                            .read<VaultCubit>()
                                            .resetVault();
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.delete_forever,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Reset Vault',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

