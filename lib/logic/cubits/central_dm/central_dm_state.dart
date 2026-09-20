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

  /// Whether another page of conversations exists — proved by the row
  /// `dm_conversations` over-fetched, never inferred from a page being full.
  final bool hasMoreConversations;

  /// peer id → unread messages from them. A zero count is an absent key, so
  /// `unreadByPeer[id] ?? 0` is the only correct way to read it.
  final Map<String, int> unreadByPeer;

  /// peer id → how much that conversation may interrupt. A peer nobody has an
  /// opinion about is absent, and [NotificationLevel.dmDefault] answers for
  /// them — which is what lets the default be changed later without touching
  /// anybody's stored rows.
  final Map<String, NotificationLevel> levelsByPeer;

  /// How many people are in each part of the friends graph, plus the rows of
  /// whichever tabs have been opened.
  ///
  /// What it gates is the whole point of the central tier having a gate at
  /// all: a conversation with somebody you are not friends with is a
  /// *request*, and it is drawn, counted and composed into differently.
  ///
  /// The rows are not loaded until a tab asks for them (central migration
  /// 014) — see [FriendBuckets].
  final FriendBuckets friends;

  /// Which friends tab is on screen, so a change to the graph can refetch the
  /// one page somebody is actually looking at. Null when the page is closed.
  final FriendBucket? openBucket;

  /// Daily-quota meter (null until first fetched).
  final int? quota;
  final int? remaining;

  /// Whether the content pane is showing the friends page.
  ///
  /// Only a phone needs to be told. On a desktop the friends page *is* the
  /// resting state, so "no conversation open" says it — but on a phone the
  /// pane with nothing open is the conversation list itself (`HomeView`), and
  /// without a flag there would be no way to navigate to friends at all.
  final bool friendsOpen;

  final String? openPeerId;
  final String? openPeerHandle;
  final DmChatStatus chatStatus;
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

  final String? error;

  /// Text to seed the add-friend field with. Set when arriving from a member's
  /// context menu, where their server display name is the best guess at a
  /// handle — central accounts are separate identities, so nothing links the
  /// two and the name is a suggestion the user has to confirm or correct.
  final String? handleQuery;

  const CentralDmState({
    this.status = CentralDmStatus.signedOut,
    this.myHandle,
    this.claiming = false,
    this.conversations = const [],
    this.conversationsLoading = false,
    this.hasMoreConversations = false,
    this.unreadByPeer = const {},
    this.levelsByPeer = const {},
    FriendBuckets? friends,
    this.openBucket,
    this.quota,
    this.remaining,
    this.friendsOpen = false,
    this.openPeerId,
    this.openPeerHandle,
    this.chatStatus = DmChatStatus.closed,
    this.messages = const [],
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
    this.hasNewerHistory = false,
    this.error,
    this.handleQuery,
  }) : friends = friends ?? FriendBuckets.empty;

  CentralDmState copyWith({
    CentralDmStatus? status,
    String? myHandle,
    bool? claiming,
    List<DmConversation>? conversations,
    bool? conversationsLoading,
    bool? hasMoreConversations,
    Map<String, int>? unreadByPeer,
    Map<String, NotificationLevel>? levelsByPeer,
    FriendBuckets? friends,
    FriendBucket? openBucket,
    int? quota,
    int? remaining,
    bool? friendsOpen,
    String? openPeerId,
    String? openPeerHandle,
    DmChatStatus? chatStatus,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    bool? hasNewerHistory,
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
      hasMoreConversations: hasMoreConversations ?? this.hasMoreConversations,
      unreadByPeer: unreadByPeer ?? this.unreadByPeer,
      levelsByPeer: levelsByPeer ?? this.levelsByPeer,
      friends: friends ?? this.friends,
      openBucket: openBucket ?? this.openBucket,
      quota: quota ?? this.quota,
      remaining: remaining ?? this.remaining,
      // Deliberately untouched by [closeConversation]: opening friends *is*
      // closing the conversation, and clearing it here would make the two
      // arguments fight in the one call that passes both.
      friendsOpen: friendsOpen ?? this.friendsOpen,
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
      hasNewerHistory: hasNewerHistory ?? this.hasNewerHistory,
      error: clearError ? null : (error ?? this.error),
      handleQuery: clearHandleQuery ? null : (handleQuery ?? this.handleQuery),
    );
  }

  NotificationLevel levelFor(String peerId) =>
      levelsByPeer[peerId] ?? NotificationLevel.dmDefault;

  /// Where the caller stands with one person — see [FriendshipState].
  ///
  /// The conversation row is the authoritative answer (central migration 014):
  /// `dm_conversations` resolves it per peer, so the client no longer holds the
  /// whole graph to work it out. Whichever friends tab is open is the fallback,
  /// and it answers for somebody reached from the friends page before a message
  /// has ever been exchanged with them — there is no conversation row to carry
  /// their state yet.
  ///
  /// A scan rather than a map, because this is asked about *one* peer: the
  /// open conversation. A row in the list has its own state on it and reads it
  /// there, without coming through here at all.
  FriendshipState stateFor(String peerId) {
    for (final conversation in conversations) {
      if (conversation.peerId == peerId) {
        return conversation.state ?? FriendshipState.none;
      }
    }
    return friends.stateOf(peerId) ?? FriendshipState.none;
  }

  /// Whether the open conversation can be typed into — which is to say
  /// whether the two of you are friends. Nothing else opens a composer.
  bool get canSendToOpen {
    final peerId = openPeerId;
    return peerId == null || stateFor(peerId).canSend;
  }

  /// Every unread central DM, **minus muted conversations and minus blocked
  /// peers**.
  ///
  /// A muted conversation keeps its own count: it still shows that something
  /// arrived in it. What muting buys is that it stops adding to the number on
  /// the outside, which is a claim that somebody wants you.
  ///
  /// A blocked peer needs no clause here any more: `dm_conversations` leaves
  /// them out of the list, so their unread counts never arrive to be skipped.
  int get totalUnread {
    var total = 0;
    for (final entry in unreadByPeer.entries) {
      if (levelFor(entry.key).isMuted) continue;
      total += entry.value;
    }
    return total;
  }

  /// What the rail's Home chip shows: unread messages plus people waiting for
  /// an answer. Somebody who has asked to reach you is exactly as worth
  /// surfacing as somebody who already can.
  int get homeBadge => totalUnread + friends.requestCount;
}
