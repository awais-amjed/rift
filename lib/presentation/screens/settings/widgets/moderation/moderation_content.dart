import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/api_response.dart';
import '../../../../../data/classes/moderation_case.dart';
import '../../../../../logic/cubits/moderation/moderation_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/empty_state.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/segmented_control.dart';
import '../../../../common/show_custom_dialog.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../../home/directory_moderation/moderation_reason_dialog.dart';
import 'hidden_listing_card.dart';
import 'moderation_case_card.dart';
import 'publisher_ban_row.dart';

enum _View { reports, hidden, banned }

/// The directory's moderation page: what has been reported, what is hidden,
/// and who may not publish. Shown only to the accounts central lists as
/// moderators, and every action on it is checked there again.
class ModerationContent extends StatefulWidget {
  const ModerationContent({super.key});

  @override
  State<ModerationContent> createState() => _ModerationContentState();
}

class _ModerationContentState extends State<ModerationContent> {
  _View _view = _View.reports;

  @override
  void initState() {
    super.initState();
    context.read<ModerationCubit>().load();
  }

  ModerationCubit get _cubit => context.read<ModerationCubit>();

  /// An action with no dialog of its own says only when it failed; success
  /// is the card leaving the list.
  Future<void> _run(Future<APIResponse> Function() action) async {
    final response = await action();
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'That did not work.');
    }
  }

  void _hide(ModerationCase item) => showCustomDialog<bool>(
    context: context,
    build: (_) => ModerationReasonDialog(
      title: 'Hide ${item.listing.name}?',
      message:
          'It leaves the directory for everyone, its reports are closed and '
          'its icon is deleted. Its owner still sees it, with your reason. '
          'You can show it again under Hidden.',
      confirmLabel: 'Hide',
      onConfirm: (reason) => _cubit.hide(item.listing, reason: reason),
    ),
  );

  void _ban(ModerationCase item) => showCustomDialog<bool>(
    context: context,
    build: (_) => ModerationReasonDialog(
      title: 'Ban @${item.listing.ownerHandle} from publishing?',
      message:
          'Everything this account has listed is hidden, with your reason, '
          'and it cannot list anything new. Lifting the ban later lets it '
          'publish again but brings no listing back.',
      confirmLabel: 'Ban',
      onConfirm: (reason) => _cubit.ban(item.listing.ownerId, reason: reason),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return BlocBuilder<ModerationCubit, ModerationState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Reports of servers and bots in the Rift directory. Hiding '
              'takes a listing out for everyone; its owner still sees it and '
              'your reason.',
              style: AppText.secondary.copyWith(color: theme.textTertiary),
            ),
            const SizedBox(height: 16),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: SegmentedControl<_View>(
                    value: _view,
                    onChanged: (v) => setState(() => _view = v),
                    options: [
                      SegmentOption(
                        value: _View.reports,
                        label: 'Reports (${state.queue.length})',
                      ),
                      SegmentOption(
                        value: _View.hidden,
                        label: 'Hidden (${state.hidden.length})',
                      ),
                      SegmentOption(
                        value: _View.banned,
                        label: 'Banned (${state.bans.length})',
                      ),
                    ],
                  ),
                ),
                AppButton(
                  label: 'Refresh',
                  variant: AppButtonVariant.secondary,
                  isLoading: state.loading,
                  onPressed: state.loading ? null : _cubit.load,
                ),
              ],
            ),
            if (state.error case final error?) ...[
              const SizedBox(height: 12),
              MessageBanner(message: error, kind: MessageBannerKind.error),
            ],
            const SizedBox(height: 16),
            if (!state.hasLoaded)
              const EmptyState(
                icon: Icons.flag_outlined,
                title: 'Loading reports',
                busy: true,
              )
            else
              ..._list(state),
          ],
        );
      },
    );
  }

  List<Widget> _list(ModerationState state) {
    final items = switch (_view) {
      _View.reports => [
        for (final item in state.queue)
          ModerationCaseCard(
            key: ValueKey('case-${item.listing.id}'),
            item: item,
            busy: state.busy.contains(item.listing.id),
            onHide: () => _hide(item),
            onDismiss: () => _run(() => _cubit.dismiss(item.listing)),
            onBan: item.listing.ownerBanned ? null : () => _ban(item),
          ),
      ],
      _View.hidden => [
        for (final listing in state.hidden)
          HiddenListingCard(
            key: ValueKey('hidden-${listing.id}'),
            listing: listing,
            busy: state.busy.contains(listing.id),
            onShow: () => _run(() => _cubit.unhide(listing)),
          ),
      ],
      _View.banned => [
        for (final ban in state.bans)
          PublisherBanRow(
            key: ValueKey('ban-${ban.userId}'),
            ban: ban,
            busy: state.busy.contains(ban.userId),
            onLift: () => _run(() => _cubit.unban(ban.userId)),
          ),
      ],
    };

    if (items.isEmpty) {
      return [
        switch (_view) {
          _View.reports => const EmptyState(
            icon: Icons.task_alt_rounded,
            title: 'Nothing to review',
            message: 'New reports of directory listings show up here.',
          ),
          _View.hidden => const EmptyState(
            icon: Icons.visibility_outlined,
            title: 'Nothing is hidden',
          ),
          _View.banned => const EmptyState(
            icon: Icons.person_outline_rounded,
            title: 'Nobody is banned from publishing',
          ),
        },
      ];
    }
    return [
      for (final item in items) ...[item, const SizedBox(height: 10)],
    ];
  }
}
