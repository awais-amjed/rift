part of 'dm_cubit.dart';

/// Whether the open server DM can be read and written yet.
enum DmChatStatus { closed, loading, ready, error }

/// DMs on the selected server: the conversation list and the one open
/// conversation.
class DmState {
  /// Conversations on the selected server, newest activity first.
  final List<DmConversation> conversations;
  final bool conversationsLoading;

  /// Whether another page of conversations follows — proved by the spare row
  /// `dm_conversations` over-fetched, never inferred from a
  /// page being full.
  final bool hasMoreConversations;

  /// The open conversation's peer, or null when none is open.
  final String? openPeerId;
  final String? openPeerName;

  final DmChatStatus chatStatus;

  /// Decrypted, verified messages of the open conversation — oldest →
  /// newest; pending optimistic sends at the end.
  final List<ChatMessage> messages;
  final bool hasMoreHistory;
  final bool isLoadingMore;

  /// Whether newer messages exist past the last loaded one.
  ///
  /// True only while a jump has put the reader in a **window** of history
  /// rather than at the live end — see the cubit's `showAround`. While it
  /// is, scrolling down loads forward, arriving messages are not appended
  /// (they belong after a stretch that is not loaded), and the view offers a
  /// way back.
  final bool hasNewerHistory;

  /// The open peer's display name while they're typing, else null.
  final String? typingPeerName;

  /// First messages from people new to us, waiting for an answer — newest
  /// first, and in [conversations] only once accepted.
  final List<DmConversation> requests;

  /// Where we stand with the open conversation's peer. [DmLinkState.open]
  /// until the server has said otherwise, so an older server never locks
  /// the composer.
  final DmLinkState openLinkState;

  /// The open peer's DM setting, known only while [openLinkState] is
  /// [DmLinkState.none] — the one case where it decides what a first message
  /// does.
  final DmPolicy? openPeerPolicy;

  /// Who we have blocked on this server.
  final Set<String> blockedIds;

  /// The open conversation's calls, over the stretch of history loaded —
  /// drawn between its messages. Newest first, as `dm_call_log` answers.
  final List<DmCall> calls;

  final String? error;

  /// [messages] are the copy this device saved, not yet replaced by what the
  /// server says: drawn while the conversation opens, and kept when it cannot.
  final bool showingSaved;

  const DmState({
    this.conversations = const [],
    this.conversationsLoading = false,
    this.hasMoreConversations = false,
    this.openPeerId,
    this.openPeerName,
    this.chatStatus = DmChatStatus.closed,
    this.messages = const [],
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
    this.hasNewerHistory = false,
    this.typingPeerName,
    this.requests = const [],
    this.openLinkState = DmLinkState.open,
    this.openPeerPolicy,
    this.blockedIds = const {},
    this.calls = const [],
    this.error,
    this.showingSaved = false,
  });

  DmState copyWith({
    List<DmConversation>? conversations,
    bool? conversationsLoading,
    bool? hasMoreConversations,
    String? openPeerId,
    String? openPeerName,
    DmChatStatus? chatStatus,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    bool? hasNewerHistory,
    String? typingPeerName,
    bool clearTyping = false,
    List<DmConversation>? requests,
    DmLinkState? openLinkState,
    DmPolicy? openPeerPolicy,
    bool clearOpenPeerPolicy = false,
    Set<String>? blockedIds,
    List<DmCall>? calls,
    String? error,
    bool clearError = false,
    bool closeConversation = false,
    bool? showingSaved,
  }) {
    return DmState(
      conversations: conversations ?? this.conversations,
      conversationsLoading: conversationsLoading ?? this.conversationsLoading,
      hasMoreConversations: hasMoreConversations ?? this.hasMoreConversations,
      openPeerId: closeConversation ? null : (openPeerId ?? this.openPeerId),
      openPeerName: closeConversation
          ? null
          : (openPeerName ?? this.openPeerName),
      chatStatus: closeConversation
          ? DmChatStatus.closed
          : (chatStatus ?? this.chatStatus),
      messages: closeConversation ? const [] : (messages ?? this.messages),
      hasMoreHistory: closeConversation
          ? false
          : (hasMoreHistory ?? this.hasMoreHistory),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasNewerHistory: closeConversation
          ? false
          : (hasNewerHistory ?? this.hasNewerHistory),
      typingPeerName: (closeConversation || clearTyping)
          ? null
          : (typingPeerName ?? this.typingPeerName),
      requests: requests ?? this.requests,
      openLinkState: closeConversation
          ? DmLinkState.open
          : (openLinkState ?? this.openLinkState),
      openPeerPolicy: (closeConversation || clearOpenPeerPolicy)
          ? null
          : (openPeerPolicy ?? this.openPeerPolicy),
      blockedIds: blockedIds ?? this.blockedIds,
      calls: closeConversation ? const [] : (calls ?? this.calls),
      error: clearError ? null : (error ?? this.error),
      showingSaved: closeConversation
          ? false
          : (showingSaved ?? this.showingSaved),
    );
  }
}
