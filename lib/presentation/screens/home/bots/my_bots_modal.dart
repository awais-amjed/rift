import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/public_bot.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/public_bots/public_bots_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/empty_state.dart';
import '../../../common/hint_card.dart';
import 'widgets/my_bot_row.dart';

/// The bots this account has listed, and the cap they count against.
///
/// The publishing half of the directory, and the counterpart of Discovery in
/// a server's settings — except that a bot has no settings screen of its own
/// to live in, because a bot is not something this client runs. So it lives
/// here, next to the browser it publishes into.
class MyBotsModal extends StatefulWidget {
  final void Function(PublicBot? editing) onEdit;
  final VoidCallback onCancel;

  const MyBotsModal({
    super.key,
    required this.onEdit,
    required this.onCancel,
  });

  @override
  State<MyBotsModal> createState() => _MyBotsModalState();
}

class _MyBotsModalState extends State<MyBotsModal> {
  @override
  void initState() {
    super.initState();
    context.read<PublicBotsCubit>().loadMine();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PublicBotsCubit, PublicBotsState>(
      builder: (context, state) {
        final cap = state.cap;
        return AppModal(
          pageOnPhone: true,
          onBack: widget.onCancel,
          title: 'Your bots',
          subtitle: cap == null
              ? 'What you have listed in the directory'
              : '${state.myListings.length} of $cap listed',
          maxWidth: K.dialogWidth,
          content: _body(context, state),
          actions: [
            AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: widget.onCancel,
            ),
            AppButton(
              label: 'List a bot',
              // The cap is the whole answer, so the button can say so rather
              // than the save discovering it.
              onPressed: state.atCap ? null : () => widget.onEdit(null),
            ),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context, PublicBotsState state) {
    if (state.savingListing && state.myListings.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (state.myListings.isEmpty) {
      return const EmptyState(
        icon: Icons.smart_toy_outlined,
        title: 'Nothing listed',
        message:
            'A bot you have written can be listed here, so anybody running a '
            'Rift server can find it. Listing it publishes a name, a '
            'description and a link to the source — nothing else, and nothing '
            'about the servers it runs on.',
      );
    }

    final cubit = context.read<PublicBotsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final bot in state.myListings)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MyBotRow(
              bot: bot,
              busy: state.savingListing,
              onEdit: () => widget.onEdit(bot),
              onRemove: () => cubit.remove(bot.id),
            ),
          ),
        if (state.atCap) ...[
          const SizedBox(height: 4),
          const HintCard(
            icon: Icons.inventory_2_outlined,
            text:
                'That is as many bots as one account may list. Withdraw one '
                'to make room — delisting hides a bot but keeps its slot, and '
                'its likes.',
          ),
        ],
      ],
    );
  }
}
