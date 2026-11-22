import '../chat_notice.dart';
import '../notification_ids.dart';

export '../notification_ids.dart' show ConversationNotificationPayload;

/// One thing worth telling the user about, found by the push background
/// isolate.
///
/// [target] is the conversation it belongs to. It does three jobs: a press on
/// the notification opens it, its [scope] is the key the high-water mark is
/// stored under, and it decides which notification this one replaces. One
/// notification per conversation, updated in place, rather than a stack of
/// them saying the same thing about the same chat — the same one the running
/// app posts for that conversation.
class WakeItem {
  final ConversationNotificationPayload target;
  final ChatNotice notice;

  /// The message this is about. The mark moves to it once it has been shown.
  final int messageId;

  const WakeItem({
    required this.target,
    required this.notice,
    required this.messageId,
  });

  String get scope => target.scope;

  /// A stable id for the notification, derived from [scope] — see
  /// [stableNotificationId]. An id that moved between wakes would stack a
  /// second notification for a conversation instead of updating the one
  /// already there.
  int get notificationId => target.notificationId;
}

/// What one source had to say when the isolate asked it.
///
/// [failed] is the difference between "nothing new here" and "could not
/// find out", which is what decides whether a wake that produced no items
/// stays quiet or falls back to saying that *something* arrived. Silence is
/// right for a doorbell about a message already announced; it is wrong for one
/// that could not be read because the network was down.
typedef WakeHarvest = ({List<WakeItem> items, bool failed});

const WakeHarvest emptyHarvest = (items: <WakeItem>[], failed: false);
const WakeHarvest failedHarvest = (items: <WakeItem>[], failed: true);

/// Whether a wake that found nothing to say still owes the generic "You have a
/// new message".
///
/// The ring carries nothing, not even which server sent it, so when one source
/// fails the isolate cannot know whether the doorbell was about that one. It
/// guesses from the rest. A server ring is a doorbell for every message in a
/// channel this member was caught up in, whatever its level, so most wakes are
/// meant to end in silence. If one server on the phone was unreachable
/// (down, or only reachable at home), any one failure turned each of those into
/// the generic notice. It is owed only when nothing could be read: [central]
/// failed (the ring came through central a moment ago, so a failure there is
/// the network), every one of [servers] failed, or there are no servers to ask.
bool owesFallback({
  required WakeHarvest central,
  required List<WakeHarvest> servers,
}) {
  if (central.items.isNotEmpty || servers.any((s) => s.items.isNotEmpty)) {
    return false;
  }
  return central.failed || servers.every((s) => s.failed);
}
