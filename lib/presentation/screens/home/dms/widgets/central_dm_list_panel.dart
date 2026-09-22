import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/hint_card.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'central_conversation_list.dart';
import 'central_handle_panel.dart';
import 'central_identity_line.dart';
import 'change_handle_dialog.dart';
import 'friends_nav_row.dart';

/// The central-DM column, in the sidebar where a server's channels would be.
///
/// Home is a *tier*, not a screen inside one: picking it swaps what the
/// sidebar column is a list of, and the conversation fills the content panel
/// exactly as a channel's chat does. Nesting a second list-and-detail pair
/// inside the content panel made central DMs look like a tool the app had
/// opened rather than one of the two places you can be.
class CentralDmListPanel extends StatelessWidget {
  const CentralDmListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final state = context.watch<CentralDmCubit>().state;
    final ready = state.status == CentralDmStatus.ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On a phone the switcher header above already carries who you are on
        // central, so the list starts straight at its rows.
        if (!context.layoutMode.isCompact)
          _buildHeader(context, themeState, state),
        if (state.status == CentralDmStatus.needsHandle || state.claiming)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: CentralHandlePanel(),
          ),
        if (ready)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: FriendsNavRow(),
          ),
        Expanded(child: _buildList(state, ready)),
      ],
    );
  }

  /// Who you are on central. No bottom border — it opens the column the way a
  /// server header does, rather than being a bar bolted across the top of it.
  ///
  /// Nothing to press here, and nothing to type into either. There used to be
  /// a handle search under it, which turned out to be a browsable index of
  /// everyone who had ever signed up; adding somebody now means knowing their
  /// handle and going to Friends, which is the row directly below.
  Widget _buildHeader(
    BuildContext context,
    ThemeState themeState,
    CentralDmState state,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Direct messages',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.panelTitle.copyWith(color: themeState.textPrimary),
          ),
          const SizedBox(height: 1),
          CentralIdentityLine(
            handle: state.myHandle,
            onChangeHandle: () => showChangeHandle(context, state.myHandle!),
          ),
        ],
      ),
    );
  }

  Widget _buildList(CentralDmState state, bool ready) {
    if (state.status == CentralDmStatus.signedOut) {
      // Top-aligned: in the column's Expanded slot a bare card is handed the
      // whole height and stretches into a tall empty box.
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: HintCard(
            icon: Icons.cloud_off_outlined,
            text:
                'Sign in to your Rift account (Settings → Cloud Backup) to '
                'message people across servers.',
          ),
        ),
      );
    }
    if (!ready) return const SizedBox.shrink();
    return const CentralConversationList();
  }
}
