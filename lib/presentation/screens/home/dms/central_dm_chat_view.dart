import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/friend.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/enums/friendship_state.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../../supabase_config.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_reply_draft.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/drop/chat_drop_zone.dart';
import '../../../common/chat/forward/show_forward_dialog.dart';
import '../../../common/chat/key_change_row.dart';
import '../../../common/chat/pins/show_pinned_messages.dart';
import '../../../common/chat/saved_copy_notice.dart';
import '../../../common/loading_block.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../mobile/widgets/mini_call_bar.dart';
import '../profile/person/show_person_profile.dart';
import '../profile/person/verification/key_check_gate.dart';
import '../profile/person/verification/key_watch.dart';
import '../profile/person/verification/show_verification.dart';
import 'widgets/dm_chat_header.dart';
import 'widgets/friends/friend_request_bar.dart';
import 'widgets/friends/not_friends_note.dart';
import 'widgets/friends/pending_request_note.dart';
import 'widgets/quota_meter.dart';

/// Over the widget budget and one job: the open central DM and its quota.
///
/// The open central-DM conversation. Central is the discovery funnel:
/// the composer footer shows the daily quota, and sends stop at zero.
class CentralDmChatView extends StatefulWidget {
  const CentralDmChatView({super.key});

  @override
  State<CentralDmChatView> createState() => _CentralDmChatViewState();
}

class _CentralDmChatViewState extends State<CentralDmChatView>
    with
        ChatScrollLoadMore<CentralDmChatView>,
        ChatReplyDraft<CentralDmChatView> {
  /// Where the pinned list sends the reader — see `ChatMessageList.jumpRequests`.
  final ValueNotifier<String?> _jumpRequests = ValueNotifier(null);

  @override
  void dispose() {
    _jumpRequests.dispose();
    super.dispose();
  }

  /// Either of the two may pin in a DM, so unpinning is always offered.
  void _showPins(BuildContext context, BuildContext anchor) {
    final cubit = context.read<CentralDmCubit>();
    unawaited(
      showPinnedMessages(
        anchor,
        load: cubit.loadPins,
        onJump: (message) => _jumpRequests.value = message.id,
        onUnpin: (message) => cubit.setPinned(message, pinned: false),
      ),
    );
  }

  @override
  void loadMoreHistory() => context.read<CentralDmCubit>().loadMoreHistory();

  @override
  void loadNewerHistory() => context.read<CentralDmCubit>().loadNewerHistory();

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final state = context.watch<CentralDmCubit>().state;
    final quotaEmpty = state.remaining != null && state.remaining! <= 0;
    final peerId = state.openPeerId;
    final handle = state.openPeerHandle ?? '';
    final friendship = peerId == null
        ? FriendshipState.none
        : state.stateFor(peerId);
    final ready = state.chatStatus == DmChatStatus.ready;
    // The saved copy is on screen while the conversation opens: what goes
    // under it is what will be there once it has, so nothing jumps.
    final opening =
        state.showingSaved &&
        (state.chatStatus == DmChatStatus.loading ||
            state.chatStatus == DmChatStatus.error);

    return KeyWatch(
      person: _person(state),
      chatKey: peerId == null ? null : _peer(state).chatPublicKey,
      child: ChatDropZone(
        child: Column(
          children: [
            DmChatHeader(
              tierIcon: Icons.public,
              tierLabel: 'Rift',
              title: '@${state.openPeerHandle ?? ''}',
              peerId: state.openPeerId,
              onOpenProfile: state.openPeerId == null
                  ? null
                  : () => unawaited(
                      showCentralProfile(context, friend: _peer(state)),
                    ),
              onVerify: state.openPeerId == null
                  ? null
                  : () => unawaited(_verify(context, state)),
              keyChanged: context.select<AppCubit, bool>(
                (c) =>
                    c.state.seenKeys[_person(state)]?.unacknowledgedChange ??
                    false,
              ),
              onShowPins: state.openPeerId == null
                  ? null
                  : (anchor) => _showPins(context, anchor),
              onClose: () => context.read<CentralDmCubit>().closeConversation(),
            ),
            Expanded(child: _buildBody(state, themeState)),
            // A phone's way back into a call, above the composer's slot.
            const MiniCallBar(),
            // There is a composer here for exactly one of the five states, and
            // every other branch is a sentence saying what would have to change.
            // None of them is a disabled field: a greyed composer with a hint in
            // it reads as something that has broken, and people retype into it.
            if (state.chatStatus == DmChatStatus.error && state.showingSaved)
              SavedCopyNotice(
                onRetry: context.read<CentralDmCubit>().retryOpen,
              ),
            if ((ready || opening) && peerId != null)
              switch (friendship) {
                FriendshipState.friends => KeyCheckGate(
                  person: _person(state),
                  name: '@$handle',
                  onCheck: () => unawaited(_verify(context, state)),
                  child: ChatComposer(
                    hintText: quotaEmpty
                        ? 'Daily limit reached — continue on a shared server'
                        : 'Message @$handle',
                    enabled: !quotaEmpty,
                    canSend: ready,
                    maxAttachmentBytes: ServerLimits.centralMaxAttachmentBytes,
                    footer: const QuotaMeter(),
                    onSend: (text, attachments, preview) =>
                        _send(context, text, attachments, preview),
                    replyingTo: replyingTo,
                    onCancelReply: cancelReply,
                  ),
                ),
                FriendshipState.incoming => FriendRequestBar(
                  peerId: peerId,
                  peerHandle: handle,
                ),
                FriendshipState.outgoing => PendingRequestNote(
                  peerId: peerId,
                  peerHandle: handle,
                ),
                // A conversation you can read and not add to: somebody unfriended,
                // or blocked and not yet cleared off this screen. Both are old
                // history with a closed door on it, and the note offers the way
                // back through.
                FriendshipState.none ||
                FriendshipState.blocked => NotFriendsNote(
                  peerId: peerId,
                  peerHandle: handle,
                  isBlocked: friendship == FriendshipState.blocked,
                ),
              },
          ],
        ),
      ),
    );
  }

  /// Whose key this conversation watches — see [KeyWatch].
  static String? _person(CentralDmState state) =>
      state.openPeerId == null ? null : 'central:${state.openPeerId}';

  /// Send, clearing the reply bar with the same press that clears the field.
  ///
  /// No ping toggle here and none offered: a DM wakes the one person in it
  /// whatever the message says, so a control for whether it does would be a
  /// switch wired to nothing.
  Future<bool> _send(
    BuildContext context,
    String text,
    List<PendingAttachment> attachments,
    Future<PendingLinkPreview?>? preview,
  ) async {
    final answering = replyingTo;
    final cubit = context.read<CentralDmCubit>();
    cancelReply();
    final refused = await cubit.sendDm(
      text,
      attachments: attachments,
      preview: preview,
      replyToId: answering?.id,
    );
    if (refused && answering != null) restoreReply(answering, pings: true);
    return refused;
  }

  /// The peer's key as the conversation carries it, against my own central
  /// account — the pair a central DM is sealed between.
  Future<void> _verify(BuildContext context, CentralDmState state) async {
    final peer = _peer(state);
    await showSafetyCodeFor(
      context,
      personName: '@${peer.handle}',
      tier: 'central',
      theirId: peer.id,
      theirChatKey: peer.chatPublicKey,
      myId: context.read<CentralDmCubit>().myUserId ?? '',
      host: Uri.parse(SupabaseConfig.supabaseUrl).host,
    );
  }

  /// The open conversation's peer as the friends graph knows them.
  ///
  /// Taken from the conversation row where there is one, because that is
  /// where their published keys are — the profile needs them to offer a
  /// message. Falling back to the id and handle alone still draws a profile;
  /// it just cannot say whether they have set encrypted chat up.
  Friend _peer(CentralDmState state) {
    final peerId = state.openPeerId!;
    for (final conversation in state.conversations) {
      if (conversation.peerId == peerId) {
        final friend = Friend.fromConversation(
          conversation,
          state.stateFor(peerId),
        );
        // A conversation row opened straight from a profile carries no key
        // yet — it is a row the list has not fetched. The friends page has
        // one, and the safety code needs it.
        if (friend.chatPublicKey != null) return friend;
        return _fromFriends(state, peerId) ?? friend;
      }
    }
    final known = _fromFriends(state, peerId);
    if (known != null) return known;
    return Friend(
      id: peerId,
      handle: state.openPeerHandle ?? '',
      state: state.stateFor(peerId),
    );
  }

  /// The peer as the friends page knows them — the row that carries their
  /// published keys.
  Friend? _fromFriends(CentralDmState state, String peerId) {
    for (final friend in state.friends.friends?.items ?? const <Friend>[]) {
      if (friend.id == peerId) return friend;
    }
    return null;
  }

  Widget _buildBody(CentralDmState state, ThemeState themeState) {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        return _buildList(state, live: true);
      // The saved copy, while the conversation opens or when it could not:
      // drawn as it is, with nothing offered that would act on it.
      case DmChatStatus.loading || DmChatStatus.error when state.showingSaved:
        return _buildList(state, live: false);
      case DmChatStatus.loading:
        return const LoadingBlock();
      case DmChatStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              state.error ?? 'Could not open this conversation.',
              textAlign: TextAlign.center,
              style: AppText.rowQuiet.copyWith(color: themeState.textTertiary),
            ),
          ),
        );
      case DmChatStatus.closed:
        return const SizedBox.shrink();
    }
  }

  /// The history. [live] is false for the saved copy: nothing on it is
  /// confirmed, so no row offers an action.
  Widget _buildList(CentralDmState state, {required bool live}) {
    final cubit = context.read<CentralDmCubit>();
    if (live) syncReplyDraft(state.openPeerId, state.messages);
    return ChatMessageList(
      // Its own list for the saved copy, so the fresh page is primed afresh
      // instead of animating everything since as an arrival.
      key: ValueKey((state.openPeerId, live)),
      messages: state.messages,
      // The default invites the first message. There is nowhere to type it
      // unless the two of you are friends, and an invitation printed above
      // the note explaining that is the screen arguing with itself.
      emptyMessage: state.canSendToOpen
          ? 'No messages yet — say hi!'
          : 'Nothing here yet.',
      controller: scrollController,
      attachmentLoader: cubit.attachmentLoader,
      // No onToggleReaction: central DMs are the first-contact tier and are
      // kept deliberately thin — reactions live on servers.
      onLookUpOriginal: cubit.fetchQuoted,
      onShowAround: live ? cubit.showAround : null,
      viewingHistory: state.hasNewerHistory,
      onReturnToPresent: cubit.returnToPresent,
      // Only the other person. Your own name here would open a profile
      // of yourself on a tier that holds one handle and two keys — the
      // handle panel already says all of it, and says it editably.
      onOpenProfile: (userId, _) {
        if (userId != state.openPeerId) return;
        unawaited(showCentralProfile(context, friend: _peer(state)));
      },
      onReply: live ? startReply : null,
      // No source server: a central DM's blobs live in central's own
      // bucket, and that is what null means to the forward service.
      onForward: live
          ? (message) => unawaited(
              showForwardDialog(
                context,
                message: message,
                currentPeerId: state.openPeerId,
              ),
            )
          : null,
      onEdit: live ? cubit.editMessage : null,
      onDelete: live ? cubit.deleteMessage : null,
      onRetry: live ? cubit.retrySend : null,
      // Pins change what the other person sees, so they take the same
      // friendship sending does, and central refuses them without it.
      onTogglePin: live && state.canSendToOpen
          ? (message) =>
                unawaited(cubit.setPinned(message, pinned: !message.isPinned))
          : null,
      jumpRequests: _jumpRequests,
      // The only two people who will ever read this. Naming anyone else
      // would light up a mention that cannot reach them.
      mentionable: {
        for (final handle in [state.myHandle, state.openPeerHandle])
          if (handle != null) handle.toLowerCase(),
      },
      keyChanges: KeyChangeLines(
        name: '@${state.openPeerHandle ?? ''}',
        at: context.select<AppCubit, List<DateTime>>(
          (c) => c.state.seenKeys[_person(state)]?.changes ?? const [],
        ),
        onCheck: () => unawaited(_verify(context, state)),
      ),
    );
  }
}
