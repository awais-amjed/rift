import 'package:flutter/material.dart';

import '../../../../../../data/classes/public_server.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_switch.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/no_central_account.dart';
import '../../../../../common/tag_editor.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../settings/widgets/section_title.dart';
import '../../../directory_moderation/listing_hidden_notice.dart';
import '../listing_draft.dart';

/// The discovery third of the server settings dialog: whether this server is
/// in the central browser, and how it reads there.
///
/// Everything below the toggle is hidden while it is off. A server that is not
/// listed has no description to write and no join link to show, and the column
/// would otherwise be mostly controls for a thing that isn't happening.
class ServerDiscoverySection extends StatelessWidget {
  final ListingDraft draft;
  final bool signedIn;

  /// This server's member count, or null while the dialog is still fetching it —
  /// in which case the disclosure names the count without quoting a number,
  /// rather than claiming a zero it hasn't checked.
  final int? memberCount;

  /// The dialog owns the draft, so every edit has to tell it to rebuild.
  final VoidCallback onChanged;

  final VoidCallback onRemove;
  final bool enabled;

  const ServerDiscoverySection({
    super.key,
    required this.draft,
    required this.signedIn,
    required this.memberCount,
    required this.onChanged,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Discovery'),
        const SizedBox(height: 4),
        Text(
          'A listed server can be found and joined by anyone with a Rift '
          'account, without an invite from you.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 14),
        if (!signedIn)
          const NoCentralAccount(
            need:
                'The directory lives on the Rift central server, so listing a '
                'server needs a Rift account — that is what makes the listing '
                'yours to edit or remove later, from any device.',
          )
        else ...[
          if (draft.listing case final listing? when listing.isHidden) ...[
            ListingHiddenNotice(reason: listing.hiddenReason),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'List in the server browser',
                  style: AppText.row.copyWith(color: themeState.textPrimary),
                ),
              ),
              AppSwitch(
                value: draft.isListed,
                onChanged: enabled
                    ? (value) {
                        draft.isListed = value;
                        onChanged();
                      }
                    : null,
              ),
            ],
          ),
          if (draft.isListed) ...[
            const SizedBox(height: 14),
            AppTextField(
              controller: draft.descriptionCtrl,
              label: 'Description',
              hint: 'What happens here, in a sentence or two',
              enabled: enabled,
              maxLines: 3,
              maxLength: PublicServer.maxDescription,
            ),
            const SizedBox(height: 16),
            TagEditor(
              controller: draft.tagCtrl,
              tags: draft.committedTags,
              onChanged: (tags) {
                draft.committedTags = tags;
                onChanged();
              },

              enabled: enabled,
            ),
            const SizedBox(height: 14),
            HintCard(
              icon: Icons.public_outlined,
              text:
                  'Published in the clear: the name and description above, '
                  "this server's address, its member count"
                  '${memberCount == null ? '' : ' ($memberCount)'} and '
                  'a join link. Not your messages, your members, or any key — '
                  'somebody joining goes through this server, exactly as if '
                  'you had sent them an invite.',
            ),
          ],
          if (draft.listing != null) ...[
            const SizedBox(height: 14),
            _JoinLink(draft: draft),
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                AppButton(
                  label: 'Reset link',
                  variant: AppButtonVariant.secondary,
                  onPressed: enabled && !draft.resetLink
                      ? () {
                          draft.resetLink = true;
                          onChanged();
                        }
                      : null,
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
      ],
    );
  }
}

/// The listing's current join link, or a note that Save will replace it.
class _JoinLink extends StatelessWidget {
  final ListingDraft draft;
  const _JoinLink({required this.draft});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'JOIN LINK',
          style: AppText.sectionLabel.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 7),
        Text(
          draft.resetLink
              ? 'A new link is created when you save.'
              : draft.listing!.inviteLink,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.meta.copyWith(
            color: draft.resetLink
                ? themeState.textTertiary
                : themeState.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'An ordinary unlimited invite on this server, carrying no '
          'permissions. Resetting it locks out anyone holding the old one; '
          'revoking it under Invite people quietly kills the listing.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
      ],
    );
  }
}
