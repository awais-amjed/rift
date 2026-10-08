import 'package:equatable/equatable.dart';

import '../enums/dm_call_outcome.dart';

/// One call between two members of a server, as one of them sees it
/// (`dm_calls`, answered by `my_dm_calls` / `start_dm_call` and the rest).
///
/// The row is the call's state and nothing more: who, when, and how it ended.
/// What was said never touches the server — the media key is derived from the
/// pair's DM key, which is why [peerChatPublicKey] rides along: the device a
/// call rings on may never have opened this conversation.
class DmCall extends Equatable {
  final String id;
  final String callerId;
  final String calleeId;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// Null while the call is going.
  final DmCallOutcome? outcome;

  /// The other person, whichever end the reader is.
  final String peerId;
  final String peerName;
  final String? peerAvatarPath;

  /// The peer's X25519 chat key (base64), which the call's media key is
  /// derived from. Null if they have never published one, which leaves a call
  /// that cannot be joined.
  final String? peerChatPublicKey;

  /// How long a caller's client lets it ring before hanging up by itself.
  /// The server's window is longer (45 s) so that an answer in flight at the
  /// last moment still lands — and since the server records any caller
  /// hang-up after fifteen seconds as `missed`, this is also how the caller
  /// tells "nobody answered" from "I hung up".
  static const ringFor = Duration(seconds: 30);

  const DmCall({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.startedAt,
    required this.peerId,
    required this.peerName,
    this.answeredAt,
    this.endedAt,
    this.outcome,
    this.peerAvatarPath,
    this.peerChatPublicKey,
  });

  factory DmCall.fromJson(Map<String, dynamic> json) {
    DateTime? at(String key) {
      final raw = json[key] as String?;
      return raw == null ? null : DateTime.parse(raw).toLocal();
    }

    return DmCall(
      id: json['id'] as String,
      callerId: json['caller_id'] as String,
      calleeId: json['callee_id'] as String,
      startedAt: at('started_at')!,
      answeredAt: at('answered_at'),
      endedAt: at('ended_at'),
      outcome: DmCallOutcome.fromString(json['outcome'] as String?),
      peerId: json['peer_id'] as String,
      peerName:
          json['peer_name'] as String? ??
          json['peer_username'] as String? ??
          'Someone',
      peerAvatarPath: json['peer_avatar_path'] as String?,
      peerChatPublicKey: json['peer_chat_public_key'] as String?,
    );
  }

  /// A list answer from `my_dm_calls` / `dm_call_log`. Rows that do not parse
  /// are dropped rather than failing the list — one bad row should not cost
  /// the whole log.
  static List<DmCall> listFrom(Object? data) {
    if (data is! List) return const [];
    final calls = <DmCall>[];
    for (final row in data) {
      if (row is! Map) continue;
      try {
        calls.add(DmCall.fromJson(Map<String, dynamic>.from(row)));
      } catch (_) {}
    }
    return calls;
  }

  bool get isEnded => endedAt != null;
  bool get isAnswered => answeredAt != null;

  /// Ringing and not yet picked up.
  bool get isRinging => !isEnded && !isAnswered;

  /// Picked up and not yet over.
  bool get isLive => !isEnded && isAnswered;

  /// Whether [myId] is the one being rung.
  bool isIncomingFor(String myId) => calleeId == myId;

  /// How long it ran, for an answered call that has ended.
  Duration? get duration {
    final from = answeredAt;
    final to = endedAt;
    if (from == null || to == null) return null;
    final length = to.difference(from);
    return length.isNegative ? Duration.zero : length;
  }

  /// The room this call is held in — the name `get_dm_call_token` gives it.
  String get roomName => 'dm-$id';

  @override
  List<Object?> get props => [
    id,
    callerId,
    calleeId,
    startedAt,
    answeredAt,
    endedAt,
    outcome,
    peerId,
    peerName,
    peerAvatarPath,
    peerChatPublicKey,
  ];
}
