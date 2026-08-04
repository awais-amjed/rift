import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import 'chip_selector.dart';
import 'copyable_field.dart';
import 'field_label.dart';
import 'invite_options.dart';
import '../../../../theme/app_text.dart';

/// The body of the invite modal: the two pickers and the generated link.
///
/// Purely presentational — the modal owns the token and the request.
class InviteForm extends StatelessWidget {
  final ThemeState themeState;
  final int expiryIndex;
  final int usesIndex;
  final ValueChanged<int> onExpirySelected;
  final ValueChanged<int> onUsesSelected;

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
          themeState: themeState,
        ),
        const SizedBox(height: 16),

        FieldLabel(label: 'Max Uses', textColor: themeState.textTertiary),
        const SizedBox(height: 8),
        ChipSelector(
          options: inviteUsesOptions.map((e) => e.label).toList(),
          selectedIndex: usesIndex,
          onSelected: onUsesSelected,
          themeState: themeState,
        ),
        const SizedBox(height: 16),

        // One field, server URL and code combined, so the invitee pastes a
        // single thing. Invites are plain: members join with baseline
        // permissions and an admin promotes them later from Members.
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
            style: AppText.secondary.copyWith(
              fontSize: 12,
              color: CustomColors.error,
            ),
          ),
        ],

        const SizedBox(height: 10),
        Text(
          'Share this link with the person you want to invite — they paste '
          'it as one field to join.',
          style: AppText.label.copyWith(
            fontSize: 11,
            color: themeState.textQuaternary,
          ),
        ),
      ],
    );
  }
}
