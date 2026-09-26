import '../../data/classes/chat_message.dart';

/// Pure pin transforms, shared by all three chat surfaces.
///
/// A pin is server-visible metadata, like a reaction: the server knows which
/// messages are pinned, never what they say. It arrives on the message row as
/// `pinned_at` and changes by doorbell, so these are the two things a cubit
/// needs — read it off a row, and set it on one loaded message.
class PinOps {
  const PinOps._();

  /// Most pins a conversation holds. The server refuses the next one
  /// (`pin_limit`); this is the number the error is worded around.
  static const int maxPins = 50;

  /// When the row's message was pinned, or null if it is not.
  static DateTime? pinnedAtOf(Map<String, dynamic> row) {
    final raw = row['pinned_at'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  /// [messages] with message [id]'s pin set to [pinnedAt] (null unpins).
  /// Everything else, including order, is untouched.
  static List<ChatMessage> withPin(
    List<ChatMessage> messages, {
    required String id,
    required DateTime? pinnedAt,
  }) => [
    for (final message in messages)
      if (message.id != id)
        message
      else if (pinnedAt == null)
        message.copyWith(clearPinned: true)
      else
        message.copyWith(pinnedAt: pinnedAt),
  ];

  /// The words for a refusal from `set_pinned`, or null for one that is not
  /// about pinning.
  static String? errorFor(String? error) {
    if (error == null) return null;
    if (error.contains('pin_limit')) {
      return 'This conversation already has $maxPins pinned messages. '
          'Unpin one first.';
    }
    if (error.contains('cannot_pin')) {
      return 'You don’t have permission to pin messages here.';
    }
    if (error.contains('not_friends')) {
      return 'You can only change pins in a chat with a friend.';
    }
    return null;
  }
}
