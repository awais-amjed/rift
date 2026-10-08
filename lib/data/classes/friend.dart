import 'package:equatable/equatable.dart';

import '../enums/friendship_state.dart';
import 'dm_conversation.dart';

/// One person in the central friends graph — a friend, a pending request
/// either way, or somebody blocked.
///
/// Carries the same identity material as a directory row, because every one of
/// these is somewhere you can start typing: a friend row opens a conversation,
/// and opening one needs the keys to seal to. It is a directory row that
/// happens to know where you stand with the person, which is why [state] lives
/// on it rather than in a map beside it.
class Friend extends Equatable {
  final String id;
  final String handle;

  /// X25519 (base64) — derives the DM key. Null if they have not published one.
  final String? chatPublicKey;

  /// Ed25519 (base64) — verifies their signatures.
  final String? signingPublicKey;

  final FriendshipState state;

  /// When this became what it is: accepted, asked, or blocked.
  final DateTime? since;

  const Friend({
    required this.id,
    required this.handle,
    required this.state,
    this.chatPublicKey,
    this.signingPublicKey,
    this.since,
  });

  /// One entry of a `friend_list()` bucket. The bucket says what the state is
  /// — the row itself carries no such column — so it is passed in.
  factory Friend.fromJson(
    Map<String, dynamic> json, {
    required FriendshipState state,
  }) {
    final since = json['since'];
    return Friend(
      id: json['id'] as String,
      handle: json['handle'] as String? ?? 'unknown',
      chatPublicKey: json['chat_public_key'] as String?,
      signingPublicKey: json['signing_public_key'] as String?,
      state: state,
      since: since is String ? DateTime.tryParse(since) : null,
    );
  }

  /// The same person seen from the conversation list, where a row carries the
  /// identity material but not the relationship. The state is passed in
  /// because a conversation does not know it — only the graph does.
  factory Friend.fromConversation(
    DmConversation conversation,
    FriendshipState state,
  ) => Friend(
    id: conversation.peerId,
    handle: conversation.peerName,
    chatPublicKey: conversation.peerChatPublicKey,
    signingPublicKey: conversation.peerSigningPublicKey,
    state: state,
  );

  /// The shape the DM surfaces open a conversation with. A friend row and a
  /// search result are the same person seen from two lists, and both lead to
  /// the same call.
  DmConversation toConversation() => DmConversation(
    peerId: id,
    peerName: handle,
    peerChatPublicKey: chatPublicKey,
    peerSigningPublicKey: signingPublicKey,
  );

  @override
  List<Object?> get props => [
    id,
    handle,
    chatPublicKey,
    signingPublicKey,
    state,
    since,
  ];
}
