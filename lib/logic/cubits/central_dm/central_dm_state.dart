part of 'central_dm_cubit.dart';

enum CentralDmStatus {
  /// No central session or locked vault — central DMs unavailable.
  signedOut,

  /// Signed in but no directory profile yet — the user must claim a handle.
  needsHandle,

  ready,
  error,
}

/// Chat status of the open central conversation (mirrors the server-DM enum
/// but kept separate — the tiers evolve independently).
enum DmChatStatus { closed, loading, ready, error }

class CentralDmState {
  final CentralDmStatus status;
  final String? myHandle;
  final bool claiming;

  /// Conversations, newest activity first. Peer names are handles.
  final List<DmConversation> conversations;
  final bool conversationsLoading;

  /// Daily-quota meter (null until first fetched).
  final int? quota;
  final int? remaining;

  final String? openPeerId;
  final String? openPeerHandle;
  final DmChatStatus chatStatus;
  final List<ChatMessage> messages;
  final bool hasMoreHistory;
  final bool isLoadingMore;
  final String? error;

  /// Text to seed the handle-search field with. Set when arriving from a
  /// member's context menu, where their server display name is the best guess
  /// at a handle — central accounts are separate identities, so nothing links
  /// the two and it can only ever be a search, not a lookup.
  final String? handleQuery;

  const CentralDmState({
    this.status = CentralDmStatus.signedOut,
    this.myHandle,
    this.claiming = false,
    this.conversations = const [],
    this.conversationsLoading = false,
    this.quota,
    this.remaining,
    this.openPeerId,
    this.openPeerHandle,
    this.chatStatus = DmChatStatus.closed,
    this.messages = const [],
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
    this.error,
    this.handleQuery,
  });

  CentralDmState copyWith({
    CentralDmStatus? status,
    String? myHandle,
    bool? claiming,
    List<DmConversation>? conversations,
    bool? conversationsLoading,
    int? quota,
    int? remaining,
    String? openPeerId,
    String? openPeerHandle,
    DmChatStatus? chatStatus,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    String? error,
    String? handleQuery,
    bool clearError = false,
    bool clearHandleQuery = false,
    bool closeConversation = false,
  }) {
    return CentralDmState(
      status: status ?? this.status,
      myHandle: myHandle ?? this.myHandle,
      claiming: claiming ?? this.claiming,
      conversations: conversations ?? this.conversations,
      conversationsLoading: conversationsLoading ?? this.conversationsLoading,
      quota: quota ?? this.quota,
      remaining: remaining ?? this.remaining,
      openPeerId: closeConversation ? null : (openPeerId ?? this.openPeerId),
      openPeerHandle: closeConversation
          ? null
          : (openPeerHandle ?? this.openPeerHandle),
      chatStatus: closeConversation
          ? DmChatStatus.closed
          : (chatStatus ?? this.chatStatus),
      messages: closeConversation ? const [] : (messages ?? this.messages),
      hasMoreHistory: closeConversation
          ? false
          : (hasMoreHistory ?? this.hasMoreHistory),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      handleQuery: clearHandleQuery ? null : (handleQuery ?? this.handleQuery),
    );
  }
}
