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

  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(
        emoji: json['emoji'] as String,
        count: (json['count'] as num).toInt(),
        mine: json['mine'] as bool? ?? false,
      );
}
