import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_modal.dart';
import '../../../common/back_chevron_button.dart';
import '../../../common/server_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../home/profile/edit/profile_edit_modal.dart';
import 'mobile_settings/settings_link_row.dart';
import 'mobile_settings/settings_media_toggle.dart';
import 'mobile_settings/settings_profile_card.dart';
import 'settings_tab.dart';

/// Settings on a phone: who you are, your mic and sound, then the sections.
///
/// The desktop's nav is only a list of section names, because the section is
/// on screen beside it. On a phone the list is a page you stand on, so each
/// row says what is behind it, and the two controls a person comes here
/// looking for mid-call — mic and sound — are right at the top, labelled,
/// rather than only as icons at the foot of the switcher.
class MobileSettingsList extends StatelessWidget {
  final ValueChanged<SettingsTab> onTabSelected;
  final VoidCallback onBack;

  const MobileSettingsList({
    super.key,
    required this.onTabSelected,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final serverId = ServerScope.idOf(context);
    final hasServer = context.select<ServerCubit, bool>(
      (c) => c.state.meOn(serverId) != null,
    );
    final call = context.watch<LiveKitCubit>().state;
    final palette = context.select<ThemeCubit, String>(
      (c) =>
          '${c.state.palette.name} · ${c.state.isDarkTheme ? 'Dark' : 'Light'}',
    );
    final backup = context.select<SupabaseBackupCubit, String?>(
      (c) => c.state.isSignedIn ? 'Signed in — backed up to the cloud' : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.borderPrimary)),
          ),
          child: Row(
            spacing: 4,
            children: [
              BackChevronButton(tooltip: 'Back to home', onPressed: onBack),
              Text(
                'Settings',
                style: AppText.sectionTitle.copyWith(color: theme.textPrimary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              if (hasServer) ...[
                SettingsProfileCard(
                  onEdit: () => showAppModal<bool>(
                    context: context,
                    modal: const ProfileEditModal(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: SettingsMediaToggle(
                      icon: call.isMicOn
                          ? Icons.mic_none_rounded
                          : Icons.mic_off,
                      label: call.isMicOn ? 'Mic on' : 'Mic off',
                      isOff: !call.isMicOn,
                      onTap: () =>
                          context.read<LiveKitCubit>().toggleMicrophone(),
                    ),
                  ),
                  Expanded(
                    child: SettingsMediaToggle(
                      icon: call.isDeafenedEffective
                          ? Icons.headset_off_rounded
                          : Icons.headset_rounded,
                      label: call.isDeafenedEffective
                          ? 'Audio off'
                          : 'Audio on',
                      isOff: call.isDeafenedEffective,
                      onTap: () => context.read<LiveKitCubit>().toggleDeafen(),
                    ),
                  ),
                ],
              ),
              _Group(
                label: 'PREFERENCES',
                rows: [
                  SettingsLinkRow(
                    icon: Icons.tune_rounded,
                    label: SettingsTab.general.label,
                    subtitle:
                        'Sensitive content, link previews, voice channels',
                    onTap: () => onTabSelected(SettingsTab.general),
                  ),
                  SettingsLinkRow(
                    icon: Icons.palette_outlined,
                    label: SettingsTab.appearance.label,
                    subtitle: 'Theme, color palette',
                    value: palette,
                    onTap: () => onTabSelected(SettingsTab.appearance),
                  ),
                  SettingsLinkRow(
                    icon: Icons.graphic_eq_rounded,
                    label: SettingsTab.voiceAndAudio.label,
                    subtitle: 'Mic test, noise suppression, sounds',
                    onTap: () => onTabSelected(SettingsTab.voiceAndAudio),
                  ),
                  SettingsLinkRow(
                    icon: Icons.cloud_outlined,
                    label: SettingsTab.backup.label,
                    subtitle: backup ?? 'Sign in, cloud backup, recovery key',
                    onTap: () => onTabSelected(SettingsTab.backup),
                  ),
                ],
              ),
              _Group(
                label: 'SUPPORT',
                rows: [
                  SettingsLinkRow(
                    icon: SettingsTab.help.icon,
                    label: SettingsTab.help.label,
                    subtitle: 'Report a bug',
                    onTap: () => onTabSelected(SettingsTab.help),
                  ),
                  SettingsLinkRow(
                    icon: SettingsTab.about.icon,
                    label: SettingsTab.about.label,
                    subtitle: 'Version, website, privacy policy',
                    onTap: () => onTabSelected(SettingsTab.about),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled card of rows, a line between each.
class _Group extends StatelessWidget {
  final String label;
  final List<Widget> rows;

  const _Group({required this.label, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
          child: Text(
            label,
            style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.bgHover,
            borderRadius: BorderRadius.circular(K.radiusCard),
            border: Border.all(color: theme.borderElevated),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, color: theme.borderPrimary),
                row,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
