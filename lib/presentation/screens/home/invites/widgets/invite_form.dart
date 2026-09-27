import 'package:flutter/material.dart';

import '../../../../../data/classes/role.dart';
import '../../../../common/chip_selector.dart';
import '../../../../common/field_label.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/segmented_control.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'copyable_field.dart';
import 'invite_options.dart';
import 'invite_role_picker.dart';

/// The body of the invite modal: the two pickers and the generated link.
///
/// Purely presentational — the modal owns the token and the request.
class InviteForm extends StatelessWidget {
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
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A decision, not a setting: `is_bot` is fixed when the link is minted
        // and there is no UPDATE grant on invites, so one link can never
        // quietly become the other kind. So it is asked
        // first, as a choice, rather than found as a switch between the
        // fields. The line under it says what actually differs, because
        // "it's a bot" tells somebody nothing about what the thing will and
        // will not be able to read.
        SegmentedControl<bool>(
          value: isBot,
          onChanged: onIsBotChanged,
          options: const [
            SegmentOption(
              value: false,
              label: 'Person',
              icon: Icons.person_outline_rounded,
            ),
            SegmentOption(
              value: true,
              label: 'Bot',
              icon: Icons.smart_toy_outlined,
            ),
          ],
        ),
        if (isBot) ...[
          const SizedBox(height: 8),
          Text(
            'Bots are listed separately and can never be given a '
            'channel\u2019s encryption key — they only see messages sent '
            'to them.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
        ],
        const SizedBox(height: 16),

        FieldLabel(label: 'Expires in', textColor: themeState.textTertiary),
        const SizedBox(height: 8),
        ChipSelector(
          options: inviteExpiryOptions.map((e) => e.label).toList(),
          selectedIndex: expiryIndex,
          onSelected: onExpirySelected,
        ),
        const SizedBox(height: 16),

        FieldLabel(label: 'Max uses', textColor: themeState.textTertiary),
        const SizedBox(height: 8),
        ChipSelector(
          options: inviteUsesOptions.map((e) => e.label).toList(),
          selectedIndex: usesIndex,
          onSelected: onUsesSelected,
        ),
        const SizedBox(height: 16),

        InviteRolePicker(
          roles: roles,
          selectedId: roleId,
          onSelected: onRoleSelected,
        ),
        if (roles.isNotEmpty) const SizedBox(height: 16),

        // One field, server URL and code combined, so the invitee pastes a
        // single thing.
        FieldLabel(label: 'Invite link', textColor: themeState.textTertiary),
        const SizedBox(height: 6),
        CopyableField(
          value: inviteLink,
          placeholder: isGenerating
              ? 'Generating…'
              : 'Generate a link to share',
          copied: copied,
          onCopy: onCopy,
        ),

        if (error != null) ...[
          const SizedBox(height: 8),
          MessageBanner(message: error!, kind: MessageBannerKind.error),
        ],

        const SizedBox(height: 10),
        Text(
          'Share this link with the person you want to invite — they paste '
          'it as one field to join.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
      ],
    );
  }
}
