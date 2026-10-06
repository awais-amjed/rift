import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/dm_conversation.dart';
import '../../../../data/enums/dm_policy.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/app_modal.dart';
import '../../../common/chip_selector.dart';
import '../../../common/field_label.dart';
import '../../../common/hint_card.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'widgets/dm_conversation_tile.dart';

/// Message requests on the selected server, and who may send them.
///
/// The setting is here, over the list, because this is where its effect is
/// seen: "ask me first" is what fills this list, and "no one new" is what
/// keeps it empty. Opening a request opens the conversation, where the
/// answer is given — accept, ignore, block or report — with the message in
/// front of you.
class DmRequestsDialog extends StatelessWidget {
  const DmRequestsDialog({super.key});

  Future<void> _setPolicy(BuildContext context, DmPolicy policy) async {
    final response = await context.read<ServerCubit>().setDmPolicy(policy);
    if (!response.success) {
      HelperMethods.showError(
        error: response.error ?? 'Could not change who can message you',
      );
    }
  }

  void _open(BuildContext context, DmConversation request) {
    Navigator.of(context).pop();
    context.read<CentralDmCubit>().closeConversation();
    context.read<DmCubit>().openConversation(
      peerId: request.peerId,
      peerName: request.peerName,
      peerChatKey: request.peerChatPublicKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final server = context.watch<ServerCubit>().state.selectedServer;
    final policy = server?.user?.dmPolicy ?? DmPolicy.everyone;
    final requests = context.watch<DmCubit>().state.requests;

    return AppModal(
      title: 'Message requests',
      subtitle: server?.name,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(
            label: 'Who can start a DM with you here',
            textColor: theme.textTertiary,
          ),
          const SizedBox(height: 8),
          ChipSelector(
            options: [for (final p in DmPolicy.values) p.label],
            selectedIndex: policy.index,
            onSelected: (i) => _setPolicy(context, DmPolicy.values[i]),
          ),
          const SizedBox(height: 6),
          Text(
            '${policy.description} People you already talk to can always '
            'message you.',
            style: AppText.meta.copyWith(color: theme.textTertiary),
          ),
          const SizedBox(height: 18),
          if (requests.isEmpty)
            HintCard(
              icon: Icons.mark_email_read_outlined,
              text: policy == DmPolicy.requests
                  ? 'No requests right now.'
                  : 'No requests. They appear here when you choose '
                        '“${DmPolicy.requests.label}”.',
            )
          else
            for (final request in requests)
              DmConversationTile(
                conversation: request,
                onServer: true,
                isSelected: false,
                unreadCount: 0,
                onTap: () => _open(context, request),
              ),
        ],
      ),
    );
  }
}

/// Open the dialog with the cubits it reads.
Future<void> showDmRequestsDialog(BuildContext context) {
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    build: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<ServerCubit>()),
        BlocProvider.value(value: context.read<DmCubit>()),
        BlocProvider.value(value: context.read<CentralDmCubit>()),
        BlocProvider.value(value: context.read<ServerMembersCubit>()),
      ],
      child: const DmRequestsDialog(),
    ),
  );
}
