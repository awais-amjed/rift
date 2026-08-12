import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../common/modal_columns.dart';
import '../listing_draft.dart';
import 'listing_details_section.dart';
import 'listing_visibility_section.dart';

/// The body of the publish dialog: how the listing reads on the left, whether
/// anyone can read it on the right.
///
/// The member count comes from the roster this client already keeps rather
/// than a fresh count, so what gets published is what the admin can see in the
/// members panel at the moment they save.
class ListingForm extends StatelessWidget {
  final ListingDraft draft;
  final String? error;
  final bool enabled;

  /// The dialog owns the draft, so every edit has to tell it to rebuild.
  final VoidCallback onChanged;

  final VoidCallback onRemove;

  const ListingForm({
    super.key,
    required this.draft,
    required this.error,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final memberCount = context.select<ServerMembersCubit, int>(
      (c) => c.state.members?.length ?? 0,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) ...[
          MessageBanner(message: error!, kind: MessageBannerKind.error),
          const SizedBox(height: 18),
        ],
        ModalColumns(
          children: [
            ListingDetailsSection(
              nameCtrl: draft.nameCtrl,
              descriptionCtrl: draft.descriptionCtrl,
              tags: draft.tags,
              onTagsChanged: (tags) {
                draft.tags = tags;
                onChanged();
              },
              themeState: themeState,
              enabled: enabled,
            ),
            ListingVisibilitySection(
              isListed: draft.isListed,
              onListedChanged: (value) {
                draft.isListed = value;
                onChanged();
              },
              inviteLink: draft.listing?.inviteLink,
              onResetLink: () {
                draft.resetLink = true;
                onChanged();
              },
              onRemove: onRemove,
              linkResetPending: draft.resetLink,
              memberCount: memberCount,
              themeState: themeState,
              enabled: enabled,
            ),
          ],
        ),
      ],
    );
  }
}
