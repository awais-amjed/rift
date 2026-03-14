import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import 'appearance_content.dart';
import 'settings_sidebar.dart';
import 'settings_tab.dart';
import 'voice_audio_content.dart';

export 'appearance_content.dart';
export 'settings_sidebar.dart';
export 'settings_tab.dart';
export 'voice_audio_content.dart';

Future<void> showSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const SettingsDialog(),
  );
}


class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  SettingsTab _activeTab = SettingsTab.appearance;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Dialog(
          backgroundColor: themeState.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 520),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left sidebar ──────────────────────────────
                SettingsSidebar(
                  activeTab: _activeTab,
                  onTabSelected: (tab) => setState(() => _activeTab = tab),
                  themeState: themeState,
                ),
                VerticalDivider(width: 1, color: themeState.borderPrimary),
                // ── Right content area ────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                        child: Row(
                          children: [
                            Icon(
                              _activeTab == SettingsTab.appearance
                                  ? Icons.palette_outlined
                                  : Icons.headset_outlined,
                              size: 20,
                              color: themeState.textPrimary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _activeTab == SettingsTab.appearance
                                        ? 'Appearance'
                                        : 'Voice & Audio',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: themeState.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _activeTab == SettingsTab.appearance
                                        ? 'Customize the look of the app.'
                                        : 'Configure voice input behavior.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: themeState.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                Icons.close,
                                color: themeState.textTertiary,
                                size: 20,
                              ),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: themeState.borderPrimary),
                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: _activeTab == SettingsTab.appearance
                              ? AppearanceContent(themeState: themeState)
                              : VoiceAudioContent(themeState: themeState),
                        ),
                      ),
                      // Footer
                      Divider(height: 1, color: themeState.borderPrimary),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: AppButton(
                          label: 'Done',
                          onPressed: () => Navigator.of(context).pop(),
                          variant: AppButtonVariant.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

