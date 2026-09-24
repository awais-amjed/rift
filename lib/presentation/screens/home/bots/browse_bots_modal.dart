import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/public_bot.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/public_bots/public_bots_cubit.dart';
import '../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/open_link.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/hint_card.dart';
import '../../../common/no_central_account.dart';
import '../servers/add_server/widgets/tag_filter_bar.dart';
import 'widgets/bot_results.dart';
import 'widgets/bot_sort_bar.dart';

/// The browse step of [BotDirectoryDialog]: every bot whose author chose to
/// be findable.
///
/// The counterpart of the server browser, and the same dialog shape on
/// purpose — but the button says **Add**, not Join, because nothing is joined
/// here. Central hands out no address for a bot: adding one mints an invite
/// on *your* server and gives you the line to run the program with. That step
/// is [AddBotModal]; this one is the shop window.
class BrowseBotsModal extends StatefulWidget {
  final void Function(PublicBot bot) onAdd;

  /// Null when this client runs no server it may add a bot to — every row
  /// then says so rather than offering a button into an empty picker.
  final bool canAdd;

  final VoidCallback onList;
  final VoidCallback onCancel;

  const BrowseBotsModal({
    super.key,
    required this.onAdd,
    required this.canAdd,
    required this.onList,
    required this.onCancel,
  });

  @override
  State<BrowseBotsModal> createState() => _BrowseBotsModalState();
}

class _BrowseBotsModalState extends State<BrowseBotsModal> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (context.read<SupabaseBackupCubit>().state.isSignedIn) {
      context.read<PublicBotsCubit>().browse();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Open a listing's source. Outside the app on purpose — reading the code
  /// is the only check anybody gets, and it is not one Rift can do for them.
  Future<void> _openSource(PublicBot bot) async {
    if (!await openExternalLink(bot.sourceUrl)) {
      HelperMethods.showError(error: 'Could not open that link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<SupabaseBackupCubit, bool>(
      (c) => c.state.isSignedIn,
    );

    return AppModal(
      pageOnPhone: true,
      onBack: widget.onCancel,
      title: 'Browse bots',
      subtitle: 'Programs you can add to a server you run',
      maxWidth: signedIn ? K.dialogWidthWide : K.dialogWidth,
      content: signedIn
          ? _browser()
          : const NoCentralAccount(
              need:
                  'The bot directory lives on the Rift central server, so '
                  'finding a bot in it needs a Rift account.',
            ),
      actions: [
        AppButton(
          label: 'Back',
          variant: AppButtonVariant.secondary,
          onPressed: widget.onCancel,
        ),
        if (signedIn)
          AppButton(
            label: 'List a bot',
            variant: AppButtonVariant.secondary,
            onPressed: widget.onList,
          ),
      ],
    );
  }

  Widget _browser() {
    return BlocBuilder<PublicBotsCubit, PublicBotsState>(
      builder: (context, state) {
        final cubit = context.read<PublicBotsCubit>();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _searchCtrl,
                    hint: 'Search by name or description',
                    autofocus: true,
                    onChanged: cubit.search,
                  ),
                ),
                BotSortBar(selected: state.sort, onSelected: cubit.setSort),
              ],
            ),
            if (state.visibleTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              TagFilterBar(
                tags: state.visibleTags,
                selected: state.tag,
                onSelected: cubit.toggleTag,
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: _resultsHeight,
              child: BotResults(
                state: state,
                onAdd: widget.canAdd ? widget.onAdd : null,
                onLike: (bot) => unawaited(cubit.toggleLike(bot.id)),
                onOpenSource: (bot) => unawaited(_openSource(bot)),
                onRetry: cubit.browse,
                onLoadMore: () => unawaited(cubit.loadMore()),
              ),
            ),
            const SizedBox(height: 12),
            HintCard(
              text: widget.canAdd
                  ? 'Anyone can list a bot here, and Rift checks none of it. '
                        'A bot is a member of your server that reads only what '
                        'it is addressed — but it is still somebody else\'s '
                        'program, so read the source before you run it.'
                  : 'Adding a bot needs a server you can manage bots on. '
                        'Everything here is still readable, and liking a bot '
                        'works from any account.',
            ),
          ],
        );
      },
    );
  }

  /// Fixed rather than sized to the results: a list that grows and shrinks as
  /// you type moves the buttons under the cursor.
  static const _resultsHeight = 340.0;
}
