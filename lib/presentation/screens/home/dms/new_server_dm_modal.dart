import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../common/app_modal.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'widgets/member_search_field.dart';

/// Starting a server DM on a phone: the member search the desktop keeps above
/// its conversation list, given a screen of its own behind the New button.
///
/// Closes itself the moment a conversation opens — picking somebody is the
/// whole of what it is for, and the conversation is pushed as a page of its own
/// underneath.
class NewServerDmModal extends StatelessWidget {
  const NewServerDmModal({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return BlocListener<DmCubit, DmState>(
      listenWhen: (a, b) =>
          a.openPeerId != b.openPeerId && b.openPeerId != null,
      listener: (context, _) => Navigator.of(context).pop(),
      child: AppModal(
        title: 'New message',
        subtitle: 'Anyone on this server, as often as you like',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            const MemberSearchField(),
            Text(
              'Server DMs stay on this server and have no daily limit. Members '
              'who have never opened Rift have no keys yet, so they cannot be '
              'messaged until they do.',
              style: AppText.meta.copyWith(color: theme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [NewServerDmModal].
void showNewServerDm(BuildContext context) =>
    showAppModal<void>(context: context, modal: const NewServerDmModal());
