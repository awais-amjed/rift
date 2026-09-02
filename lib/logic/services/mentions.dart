import '../../data/classes/server_member.dart';
import 'message_markup.dart';

/// Who a message names.
///
/// [userIds] are the members it named by username; [all] is whether it said
/// `@all`. Kept apart on purpose — `@all` is one flag, not a list of everyone,
/// because a list of everyone is exactly the thing a mention cap exists to
/// stop somebody writing by hand.
typedef MentionTargets = ({List<String> userIds, bool all});

/// Reading `@names` out of a message, and deciding which ones mean *you*.
///
/// Pure, and the single place that says what `@all` means. Four things ask
/// that question — the composer working out who to tell the server about, the
/// renderer deciding what to highlight, the desktop notifier, and the push
/// isolate — and a disagreement between any two of them is somebody either
/// missing a ping or getting one they were never sent.
class Mentions {
  const Mentions._();

  /// The name that means everybody. Reserved: `users_username_not_reserved`
  /// (self-hosted migration 012) stops anyone being called this, so `@all` can
  /// never be ambiguous between a room and a person.
  static const everyone = 'all';

  /// The most names one message may carry to the server. Matches the ceiling
  /// the database applies, so a client that would be trimmed there is trimmed
  /// here instead — the same message either way, without a round trip that
  /// quietly disagrees with what was sent.
  static const maxTargets = 50;

  /// The set of names that count as "you" for [username].
  ///
  /// Always includes [everyone]: being in the room when somebody says `@all`
  /// is being named, and every path that highlights or announces a mention has
  /// to think so or they will contradict each other.
  static Set<String> mentionableFor(String? username) {
    final name = username?.trim().toLowerCase();
    return {everyone, if (name != null && name.isNotEmpty) name};
  }

  /// Everybody a message here can actually name.
  ///
  /// **Not bots.** A normal message that mentions one does nothing: a bot only
  /// ever receives what is addressed to it with `/`, and `messages_select` will
  /// not return anything else however the text is written (BOTS.md §4). Two
  /// messages that look identical must not have different protection, so the
  /// habit is refused rather than half-supported.
  ///
  /// **Not somebody who cannot open the channel.** [audience] is the resolved
  /// set from `channel_audience`, and null means everybody — a public channel,
  /// where the roster is already the answer. In a private one the server strips
  /// an outsider from `mentions` on the way in (`validate_message_mentions`),
  /// so offering them here is offering a ping that will not happen, and would
  /// also spend the one thing the writer might want back: telling somebody
  /// they are not in the room.
  ///
  /// Both refusals have to reach every surface or they become a lie somewhere:
  /// an `@` menu that offers a name, a name that lights up as though it
  /// arrived, a mention recorded in the clear that wakes nobody. One list, so
  /// they cannot disagree.
  static Iterable<ServerMember> among(
    Iterable<ServerMember> members, {
    Set<String>? audience,
  }) => members.where(
    (member) => !member.isBot && (audience?.contains(member.id) ?? true),
  );

  /// A roster in the shape [resolve] wants: username → user id.
  ///
  /// Here rather than at the call site because it is the half that decides
  /// *who can be named at all*, and a caller that built it from display names
  /// would produce a mention that highlights and pings the wrong person —
  /// display names can be changed by their owner and can collide, which is
  /// exactly why they are not the key.
  static Map<String, String> rosterOf(
    Iterable<ServerMember> members, {
    Set<String>? audience,
  }) => {
    for (final member in among(members, audience: audience))
      member.username: member.id,
  };

  /// Whether [text] names the person called [username].
  static bool namesMe(String text, {String? username}) =>
      mentionsAnyOf(text, mentionableFor(username));

  /// Who [text] names, resolved against a roster.
  ///
  /// [idsByUsername] is username → user id; case is ignored. A name nobody
  /// answers to is dropped rather than guessed at, and so is [excludeUserId] —
  /// normally the sender, because a message that pings its own author is only
  /// ever a mistake.
  ///
  /// Parsed with the same parser that draws the message, so an `@name` inside
  /// a code span or behind a backslash is not a mention here either. Reading
  /// it with a regex instead is how `@example` in a code sample ends up
  /// waking somebody's phone at 3am.
  static MentionTargets resolve(
    String text, {
    required Map<String, String> idsByUsername,
    String? excludeUserId,
  }) {
    if (text.isEmpty) return (userIds: const <String>[], all: false);

    final roster = {
      for (final entry in idsByUsername.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final ids = <String>{};
    var all = false;

    for (final span in parseMessageMarkup(text)) {
      final mention = span.mention?.toLowerCase();
      if (mention == null) continue;
      if (mention == everyone) {
        all = true;
        continue;
      }
      final id = roster[mention];
      if (id == null || id == excludeUserId) continue;
      ids.add(id);
      if (ids.length >= maxTargets) break;
    }

    return (userIds: ids.toList(growable: false), all: all);
  }
}
