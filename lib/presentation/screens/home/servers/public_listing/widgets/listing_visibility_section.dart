import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_switch.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../theme/app_text.dart';
import '../../../../settings/widgets/section_title.dart';

/// Whether the listing is in the browser, what publishing it actually
/// discloses, and the way back out.
///
/// The disclosure note is not boilerplate. Everything else central holds is
/// encrypted because it belongs to the user; this row is deliberately
/// plaintext, and an admin should read the difference before agreeing to it
/// rather than after.
class ListingVisibilitySection extends StatelessWidget {
  final bool isListed;
  final ValueChanged<bool> onListedChanged;

  /// Null until the server has been published once — before that there is no
  /// row to withdraw and no join link to show.
  final String? inviteLink;

  final VoidCallback? onResetLink;
  final VoidCallback? onRemove;

  /// A reset was asked for and hasn't been saved yet. The new code is minted
  /// on save rather than on the click, so backing out of the dialog leaves the
  /// old link working — resetting is destructive to everyone holding it.
  final bool linkResetPending;

  /// What the member count will be saved as, which is a number the admin
  /// should be able to see before it is published on their behalf.
  final int memberCount;

  final ThemeState themeState;
  final bool enabled;

  const ListingVisibilitySection({
    super.key,
    required this.isListed,
    required this.onListedChanged,
    required this.inviteLink,
    required this.onResetLink,
    required this.onRemove,
    this.linkResetPending = false,
    required this.memberCount,
    required this.themeState,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(label: 'Discovery', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          'A listed server can be found and joined by anyone with a Rift '
          'account, without an invite from you.',
          style: AppText.label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: themeState.textTertiary,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'List in the server browser',
                style: AppText.row.copyWith(
                  fontSize: 13,
                  color: themeState.textPrimary,
                ),
              ),
            ),
            AppSwitch(
              value: isListed,
              onChanged: enabled ? onListedChanged : null,
            ),
          ],
        ),
        const SizedBox(height: 14),
        HintCard(
          icon: Icons.public_outlined,
          text:
              'Published in the clear: the name, description and tags above, '
              'this server\'s address, its member count ($memberCount), and a '
              'join link. Not your messages, your members, or any key — a '
              'stranger joining goes through your server, exactly as if you '
              'had sent them an invite.',
        ),
        if (inviteLink != null) ...[
          const SizedBox(height: 14),
          Text(
            'JOIN LINK',
            style: AppText.sectionLabel.copyWith(
              fontSize: 10.5,
              letterSpacing: 1.2,
              color: themeState.textTertiary,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            linkResetPending
                ? 'A new link is created when you save.'
                : inviteLink!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.meta.copyWith(
              fontSize: 11.5,
              color: linkResetPending
                  ? themeState.textTertiary
                  : themeState.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'An ordinary unlimited invite on your own server, carrying no '
            'permissions. Resetting it locks out anyone holding the old one; '
            'revoking it there quietly kills the listing.',
            style: AppText.label.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: themeState.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              AppButton(
                label: 'Reset link',
                variant: AppButtonVariant.secondary,
                onPressed: enabled && !linkResetPending ? onResetLink : null,
              ),
              AppButton(
                label: 'Remove listing',
                variant: AppButtonVariant.danger,
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
