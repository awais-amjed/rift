/// An aggregated emoji reaction on a message — how many people used [emoji] and
/// whether the local user is one of them. Reactions are NOT E2E (the server
/// sees them); see ARCHITECTURE.md §4.
class MessageReaction {
  final String emoji;
  final int count;
  final bool mine;

  const MessageReaction({
    required this.emoji,
    required this.count,
    required this.mine,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
        emoji: json['emoji'] as String,
        count: (json['count'] as num).toInt(),
        mine: json['mine'] as bool? ?? false,
      );

  /// Parse an aggregated list off a message row or a reaction read. Anything
  /// that isn't a list — absent, or a message nobody has reacted to — is no
  /// reactions rather than an error.
  static List<MessageReaction> listFrom(Object? raw) => raw is List
      ? [
          for (final entry in raw)
            MessageReaction.fromJson((entry as Map).cast<String, dynamic>()),
        ]
      : const [];
}
