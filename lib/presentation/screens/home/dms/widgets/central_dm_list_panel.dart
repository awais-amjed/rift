import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/hint_card.dart';
import '../../../../theme/app_text.dart';
import '../../channels/channel_list/widgets/section_header.dart';
import 'central_handle_panel.dart';
import 'dm_conversation_tile.dart';
import 'handle_search_field.dart';

/// The central-DM column, in the sidebar where a server's channels would be.
///
/// Home is a *tier*, not a screen inside one: picking it swaps what the
/// sidebar column is a list of, and the conversation fills the content panel
/// exactly as a channel's chat does. Nesting a second list-and-detail pair
/// inside the content panel made central DMs look like a tool the app had
/// opened rather than one of the two places you can be.
class CentralDmListPanel extends StatefulWidget {
  const CentralDmListPanel({super.key});

  @override
  State<CentralDmListPanel> createState() => _CentralDmListPanelState();
}

class _CentralDmListPanelState extends State<CentralDmListPanel> {
  // Owned here rather than by the field, so the "+" and the member context
  // menu can both drive it.
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Seeded by the cubit when you arrive from "Message on Central". Setting
  /// the text is what runs the search — the field listens to its controller.
  void _consumeSeededQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: query.length,
    );
    _searchFocus.requestFocus();
    context.read<CentralDmCubit>().setHandleQuery(null);
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final state = context.watch<CentralDmCubit>().state;
    final ready = state.status == CentralDmStatus.ready;

    return BlocListener<CentralDmCubit, CentralDmState>(
      listenWhen: (a, b) => a.handleQuery != b.handleQuery,
      listener: (context, state) {
        final query = state.handleQuery;
        if (query != null) _consumeSeededQuery(query);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(themeState, state, ready),
          if (ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: HandleSearchField(
                controller: _searchController,
                focusNode: _searchFocus,
              ),
            ),
          if (state.status == CentralDmStatus.needsHandle || state.claiming)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: CentralHandlePanel(),
            ),
          Expanded(child: _buildList(themeState, state, ready)),
        ],
      ),
    );
  }

  /// Who you are on central, and the way to start a conversation. No bottom
  /// border — it opens the column the way a server header does, rather than
  /// being a bar bolted across the top of it.
  Widget _buildHeader(ThemeState themeState, CentralDmState state, bool ready) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Direct messages',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.panelTitle.copyWith(
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                _buildIdentity(themeState, state),
              ],
            ),
          ),
          if (ready) _buildNewButton(themeState),
        ],
      ),
    );
  }

  Widget _buildIdentity(ThemeState themeState, CentralDmState state) {
    final handle = state.myHandle;
    return Row(
      spacing: 5,
      children: [
        Icon(Icons.public, size: 11, color: themeState.accentBright),
        if (handle != null)
          Flexible(
            child: Text(
              '@$handle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Mono: a handle is an identifier, and it reads as one.
              style: AppText.figure.copyWith(
                fontWeight: FontWeight.w400,
                color: themeState.textTertiary,
              ),
            ),
          ),
        Text(
          handle == null ? 'central account' : '· central account',
          style: AppText.label.copyWith(
            fontWeight: FontWeight.w400,
            color: themeState.textQuaternary,
          ),
        ),
      ],
    );
  }

  /// Focuses the search field rather than opening anything: starting a
  /// conversation *is* finding someone, and the field for that is right below.
  Widget _buildNewButton(ThemeState themeState) {
    final radius = BorderRadius.circular(9);
    return Tooltip(
      message: 'Find someone',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: themeState.primary.withValues(alpha: 0.12),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: _searchFocus.requestFocus,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: themeState.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 17,
              color: themeState.accentBright,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeState themeState, CentralDmState state, bool ready) {
    if (state.status == CentralDmStatus.signedOut) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: HintCard(
          icon: Icons.cloud_off_outlined,
          text:
              'Sign in to your Rift account (Settings → Cloud Backup) to '
              'message people across servers.',
        ),
      );
    }
    if (!ready) return const SizedBox.shrink();

    final conversations = state.conversations;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: conversations.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const SectionHeader(label: 'Conversations');
        }
        if (index > conversations.length) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(2, 14, 2, 12),
            child: HintCard(
              text:
                  'Central DMs are for finding each other. For longer chats, '
                  'move to a server you share.',
            ),
          );
        }
        final conversation = conversations[index - 1];
        return DmConversationTile(
          conversation: conversation,
          isSelected: conversation.peerId == state.openPeerId,
          themeState: themeState,
          onTap: () {
            // Only one DM surface is open at a time.
            context.read<DmCubit>().closeConversation();
            context.read<CentralDmCubit>().openConversation(
              peerId: conversation.peerId,
              peerHandle: conversation.peerName,
              peerChatKey: conversation.peerChatPublicKey,
              peerSigningKey: conversation.peerSigningPublicKey,
            );
          },
        );
      },
    );
  }
}
