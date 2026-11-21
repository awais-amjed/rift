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
///
/// What counts as new is a conversation's newest message moving *forward*.
/// Kept as a set of message ids seen, deleting the newest message made the
/// one before it the head, unseen, and it was announced as if it had just
/// arrived.
class NewMessageNotifier {
  /// The newest message id seen in each conversation, by peer.
  final Map<String, int> _newest = {};
  bool _primed = false;

  /// Whether a scan has been made since the last [reset].
  bool get primed => _primed;

  /// Forget all state — call when the identity/server context changes so the
  /// next scan re-primes instead of notifying for a different account's chats.
  void reset() {
    _newest.clear();
    _primed = false;
  }

  /// Inspect the latest conversation snapshot. [titleFor] builds the
  /// notification title for a conversation (e.g. its peer name), and
  /// [payloadFor] what a press on it opens. A conversation [muted] answers
  /// true for raises nothing, though what arrived in it is still counted seen:
  /// unmuted later, it does not announce what came while it was quiet.
  ///
  /// Answers the conversations that had something new to announce, whether or
  /// not the window's focus let it be shown.
  List<DmConversation> scan(
    Iterable<DmConversation> conversations, {
    required String Function(DmConversation) titleFor,
    String? Function(DmConversation)? payloadFor,
    bool Function(DmConversation)? muted,
  }) {
    final fresh = <DmConversation>[];
    for (final convo in conversations) {
      final last = convo.lastMessage;
      final id = int.tryParse(last?.id ?? '');
      if (last == null || id == null) continue;
      final before = _newest[convo.peerId];
      if (before != null && id <= before) continue;
      // Counted whoever sent it, so a later look back past it is not news.
      _newest[convo.peerId] = id;
      // A locked message has no words to show, and a notification saying
      // nothing is worse than none — the same rule a channel follows.
      if (last.isMine || last.isLocked) continue;
      // Only once primed, so the initial snapshot is absorbed silently.
      if (_primed && !(muted?.call(convo) ?? false)) fresh.add(convo);
    }
    _primed = true;
    if (fresh.isEmpty || WindowFocusService.instance.isFocused) return fresh;
    for (final convo in fresh) {
      NotificationService.instance.showMessage(
        title: titleFor(convo),
        body: convo.lastMessage!.text,
        payload: payloadFor?.call(convo),
      );
    }
    return fresh;
  }
}
