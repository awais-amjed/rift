import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import 'chip_selector.dart';
import 'copyable_field.dart';
import 'field_label.dart';
import 'invite_options.dart';
import '../../../../theme/app_text.dart';
import '../../../settings/widgets/setting_toggle_row.dart';
import '../../../../../data/classes/role.dart';
import 'invite_role_picker.dart';

/// The body of the invite modal: the two pickers and the generated link.
///
/// Purely presentational — the modal owns the token and the request.
class InviteForm extends StatelessWidget {
  final ThemeState themeState;
  final int expiryIndex;
  final int usesIndex;
  final ValueChanged<int> onExpirySelected;
  final ValueChanged<int> onUsesSelected;

  /// Whether this link will mint a bot rather than a member.
  final bool isBot;

  /// Roles the minter may hand out — everything below their own rank. Empty
  /// where they hold no `MANAGE_ROLES`, which hides the picker entirely.
  final List<Role> roles;
  final String? roleId;
  final ValueChanged<String?> onRoleSelected;
  final ValueChanged<bool> onIsBotChanged;

  final String? inviteLink;
  final bool isGenerating;
  final bool copied;
  final VoidCallback? onCopy;
  final String? error;

  const InviteForm({
    super.key,
    required this.themeState,
    required this.expiryIndex,
    required this.usesIndex,
    required this.onExpirySelected,
    required this.onUsesSelected,
    required this.isBot,
    required this.roles,
    required this.roleId,
    required this.onRoleSelected,
    required this.onIsBotChanged,
    required this.inviteLink,
    required this.isGenerating,
    required this.copied,
    required this.onCopy,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: 'Expires In', textColor: themeState.textTertiary),
        const SizedBox(height: 8),
        ChipSelector(
          options: inviteExpiryOptions.map((e) => e.label).toList(),
          selectedIndex: expiryIndex,
          onSelected: onExpirySelected,
        ),
        const SizedBox(height: 16),

        FieldLabel(label: 'Max Uses', textColor: themeState.textTertiary),
        const SizedBox(height: 8),
        ChipSelector(
          options: inviteUsesOptions.map((e) => e.label).toList(),
          selectedIndex: usesIndex,
          onSelected: onUsesSelected,
        ),
        const SizedBox(height: 16),

        // A decision, not a setting: `is_bot` is fixed when the link is minted
        // and there is no UPDATE grant on invites, so one link can never
        // quietly become the other kind (migration 014). The description says
        // what actually differs, because "it's a bot" tells somebody nothing
        // about what the thing will and will not be able to read.
        InviteRolePicker(
          themeState: themeState,
          roles: roles,
          selectedId: roleId,
          onSelected: onRoleSelected,
        ),
        if (roles.isNotEmpty) const SizedBox(height: 16),

        SettingToggleRow(
          themeState: themeState,
          title: 'This invite is for a bot',
          description:
              'Bots are listed separately and can never be given a '
              'channel\u2019s encryption key — they only see messages sent '
              'to them.',
          value: isBot,
          onChanged: onIsBotChanged,
        ),
        const SizedBox(height: 16),

        // One field, server URL and code combined, so the invitee pastes a
        // single thing.
        FieldLabel(label: 'Invite Link', textColor: themeState.textTertiary),
        const SizedBox(height: 6),
        CopyableField(
          value: inviteLink,
          placeholder: isGenerating
              ? 'Generating...'
              : 'Click generate to create an invite link',
          copied: copied,
          onCopy: onCopy,
          bgColor: themeState.bgSecondary,
          borderColor: themeState.borderPrimary,
          textColor: themeState.textTertiary,
          placeholderColor: themeState.textQuaternary,
        ),

        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: AppText.secondary.copyWith(color: CustomColors.error),
          ),
        ],

        const SizedBox(height: 10),
        Text(
          'Share this link with the person you want to invite — they paste '
          'it as one field to join.',
          style: AppText.secondary.copyWith(color: themeState.textQuaternary),
        ),
      ],
    );
  }
}
