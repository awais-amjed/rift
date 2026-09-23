import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../../logic/services/host_platform.dart';
import '../../common/app_panel.dart';
import '../../common/back_chevron_button.dart';
import '../../common/canvas_backdrop.dart';
import '../../common/confirm_dialog.dart';
import '../../common/icon_tile.dart';
import '../../responsive/shell_scope.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';
import 'widgets/appearance_content.dart';
import 'widgets/backup_content/backup_content.dart';
import 'widgets/general_content.dart';
import 'widgets/mobile_settings_list.dart';
import 'widgets/settings_sidebar.dart';
import 'widgets/settings_tab.dart';
import 'widgets/voice_audio_content.dart';

export 'widgets/appearance_content.dart';
export 'widgets/backup_content/backup_content.dart';
export 'widgets/settings_sidebar.dart';
export 'widgets/settings_tab.dart';
export 'widgets/voice_audio_content.dart';

/// Over the widget budget and one job: the settings layout, one pane or two.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsTab _activeTab = SettingsTab.appearance;

  /// Whether a tab's contents are showing, on the widths where the nav and the
  /// contents cannot both be.
  ///
  /// Settings is two panels side by side, and neither survives being halved:
  /// the nav is a list of labels and the contents are full of controls with
  /// their own minimum widths. So on a phone they become a list and a detail
  /// page, which is what every settings screen on a phone already is, and this
  /// says which of the two is showing. Ignored entirely at wider sizes, where
  /// both are on screen and there is nothing to be in front of anything else.
  bool _detailOpen = false;

  String get _tabTitle => switch (_activeTab) {
    SettingsTab.appearance => 'Appearance',
    SettingsTab.general => 'General',
    SettingsTab.voiceAndAudio => 'Voice & audio',
    SettingsTab.backup => 'Cloud backup',
  };

  IconData get _tabIcon => switch (_activeTab) {
    SettingsTab.appearance => Icons.palette_outlined,
    SettingsTab.general => Icons.tune_rounded,
    SettingsTab.voiceAndAudio => Icons.headset_outlined,
    SettingsTab.backup => Icons.cloud_outlined,
  };

  /// Wipes the vault and server list from this device and returns to
  /// onboarding. Irreversible without a cloud or file backup.
  Future<void> _resetVault() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Reset vault?',
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
    await context.read<VaultCubit>().resetVault();
  }

  void _selectTab(SettingsTab tab, {required bool compact}) {
    setState(() {
      _activeTab = tab;
      if (compact) _detailOpen = true;
    });
  }

  Widget _buildHeader(ThemeState themeState, {required bool showBack}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(showBack ? 12 : 24, 18, 24, 16),
      child: Row(
        spacing: 12,
        children: [
          // The way back to the list. The nav panel's own back arrow leaves
          // Settings altogether, and is not on screen here anyway.
          if (showBack)
            BackChevronButton(
              tooltip: 'All settings',
              onPressed: () => setState(() => _detailOpen = false),
            ),
          // The tab's own mark, so the content panel says which section you
          // are in as loudly as the nav row you clicked to get here.
          IconTile(
            icon: _tabIcon,
            color: themeState.accentBright,
            size: 36,
            radius: K.radiusRow,
            iconSize: 19,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // No subtitle: the nav row already named the tab, and a
                // sentence under the title said the same thing again.
                Text(
                  _tabTitle,
                  style: AppText.sectionTitle.copyWith(
                    color: themeState.textPrimary,
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
    final themeState = context.theme;
    return PopScope(
      // On a phone a section is a page in front of the list, so back
      // returns to the list before it leaves settings.
      canPop: !(context.layoutMode.isCompact && _detailOpen),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _detailOpen = false);
      },
      child: Scaffold(
        body: BlocBuilder<AppCubit, AppState>(
          buildWhen: (prev, curr) =>
              prev.titleBarVisible != curr.titleBarVisible,
          builder: (context, appState) {
            final compact = context.layoutMode.isCompact;
            final topOffset = !HostPlatform.drawsOwnWindowChrome
                ? 0.0
                : (appState.titleBarVisible ? K.titleBarHeight : 0.0);
            final gutter = context.layoutMode.panelGutter;
            return CanvasBackdrop(
              child: Padding(
                // No gutter on a phone: the panel is the screen there and
                // holds its own content clear of the cutouts. See
                // `LayoutMode.panelsAreIslands`.
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  topOffset == 0 ? gutter : topOffset,
                  gutter,
                  gutter,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Left nav panel ───────────────────────────
                    // Full width on a phone, where it is the list half of a
                    // list-and-detail pair rather than a column beside one.
                    if (!compact || !_detailOpen)
                      _NavPanel(
                        expand: compact,
                        child: compact
                            ? SafeArea(
                                bottom: false,
                                child: MobileSettingsList(
                                  onTabSelected: (tab) =>
                                      _selectTab(tab, compact: true),
                                  onBack: () => context.pop(),
                                ),
                              )
                            : SettingsSidebar(
                                activeTab: _activeTab,
                                onTabSelected: (tab) =>
                                    _selectTab(tab, compact: compact),
                                onBack: () => context.pop(),
                              ),
                      ),
                    if (!compact) SizedBox(width: gutter),
                    // ── Right content panel ──────────────────────
                    if (!compact || _detailOpen)
                      Expanded(
                        child: AppPanel(
                          color: themeState.bgContent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SafeArea(
                                bottom: false,
                                child: _buildHeader(
                                  themeState,
                                  showBack: compact && _detailOpen,
                                ),
                              ),
                              Divider(
                                height: 1,
                                color: themeState.borderPrimary,
                              ),
                              Expanded(
                                // Full width, so the scrollbar sits at
                                // the panel's edge. The column above is
                                // start-aligned, which let the scroll
                                // view shrink to its content — a tab
                                // held to a reading measure put the bar
                                // halfway across the panel.
                                child: SizedBox(
                                  width: double.infinity,
                                  child: SingleChildScrollView(
                                    padding: EdgeInsets.all(compact ? 16 : 24),
                                    // Loosened again inside, or the
                                    // full width arrives tight and a
                                    // tab's reading measure is ignored.
                                    // [K.settingsMeasure] is that measure,
                                    // applied here so a pane cannot opt out
                                    // of it — three of the four used to.
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: K.settingsMeasure,
                                        ),
                                        child: switch (_activeTab) {
                                          SettingsTab.appearance =>
                                            const AppearanceContent(),
                                          SettingsTab.general =>
                                            const GeneralContent(),
                                          SettingsTab.voiceAndAudio =>
                                            const VoiceAudioContent(),
                                          SettingsTab.backup => BackupContent(
                                            onResetVault: _resetVault,
                                          ),
                                        },
                                      ),
                                    ),
                                  ),
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
      ),
    );
  }
}

/// The settings nav, at its fixed width beside the contents or filling the
/// window when it is the only thing on it.
///
/// [AppPanel] takes a width, not a flex, so the two cases cannot be expressed
/// by passing it a different number — an [Expanded] has to wrap it instead.
class _NavPanel extends StatelessWidget {
  final bool expand;
  final Widget child;

  const _NavPanel({required this.expand, required this.child});

  @override
  Widget build(BuildContext context) {
    if (expand) return Expanded(child: AppPanel(child: child));
    return AppPanel(width: K.settingsNavWidth, child: child);
  }
}
