import '../chat_notice.dart';

/// One thing worth telling the user about, found by the push background
/// isolate.
///
/// [scope] names the conversation it belongs to — a channel id, or a peer id
/// prefixed by where they live. It does two jobs: it is the key the
/// high-water mark is stored under, and it decides which notification this one
/// replaces. One notification per conversation, updated in place, rather than
/// a stack of them saying the same thing about the same chat.
class WakeItem {
  final String scope;
  final ChatNotice notice;

  /// The message this is about. The mark moves to it once it has been shown.
  final int messageId;

  const WakeItem({
    required this.scope,
    required this.notice,
    required this.messageId,
  });

  /// A stable id for the notification, derived from [scope].
  ///
  /// FNV-1a rather than [Object.hashCode], which Dart does not promise to keep
  /// the same between runs — and every wake is a new run. An id that moved
  /// would stack a second notification for a conversation instead of updating
  /// the one already there.
  int get notificationId {
    var hash = 0x811c9dc5;
    for (final unit in scope.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
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
