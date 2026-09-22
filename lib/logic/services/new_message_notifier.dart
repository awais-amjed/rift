import '../../data/classes/dm_conversation.dart';
import 'notification_service.dart';
import 'window_focus_service.dart';

/// Diffs successive conversation-list snapshots and fires a notification for
/// each newly-arrived *incoming* message, once, when the window is unfocused.
///
/// DM inbox topics are per-user (not per-conversation), so the conversation
/// list is the one place that learns of new messages across every peer — this
/// rides on the existing `refreshConversations` calls. The first scan after a
/// [reset] only primes the seen-set, so opening the app never replays history
/// as a burst of notifications.
class NewMessageNotifier {
  final Set<String> _seen = <String>{};
  bool _primed = false;

  /// Forget all state — call when the identity/server context changes so the
  /// next scan re-primes instead of notifying for a different account's chats.
  void reset() {
    _seen.clear();
    _primed = false;
  }

  /// Inspect the latest conversation snapshot. [titleFor] builds the
  /// notification title for a conversation (e.g. its peer name).
  void scan(
    Iterable<DmConversation> conversations, {
    required String Function(DmConversation) titleFor,
  }) {
    final fresh = <DmConversation>[];
    for (final convo in conversations) {
      final last = convo.lastMessage;
      if (last == null || last.isMine) continue;
      final key = '${convo.peerId}:${last.id}';
      // add() is true only the first time we see this message. Notify only
      // once primed, so the initial snapshot is absorbed silently.
      if (_seen.add(key) && _primed) fresh.add(convo);
    }
    _primed = true;
    if (fresh.isEmpty || WindowFocusService.instance.isFocused) return;
    for (final convo in fresh) {
      NotificationService.instance.showMessage(
        title: titleFor(convo),
        body: convo.lastMessage!.text,
      );
    }
  }
}
