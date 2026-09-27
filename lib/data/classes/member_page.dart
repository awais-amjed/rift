import 'paged.dart';
import 'server_member.dart';

/// One page of the roster, and where the next one resumes.
///
/// The roster used to arrive whole, so nothing needed a type: a list was the
/// answer and the end of it was the end of the server. Now it arrives in pages
/// (`member_directory`), and the two facts a caller needs — the rows, and whether
/// there are more — travel together or they drift apart. A "load more" button
/// wired to a bare list has to guess, and guessing from a full page is the bug
/// [Paging.split] exists to avoid.
class MemberPage extends Paged<ServerMember> {
  /// How many members one page asks for.
  ///
  /// Comfortably more than a sidebar shows at once, so scrolling normally
  /// finds the next page already loaded, and comfortably under
  /// `app.member_page_max()`, so the database never has to clamp us.
  static const int pageSize = 50;

  /// The rows, named for what they are at every call site that reads them.
  List<ServerMember> get members => items;

  const MemberPage({
    required List<ServerMember> members,
    required super.hasMore,
  }) : super(items: members);

  /// A settled empty roster: no rows, and nothing more coming. Distinct from
  /// null, which callers use for "not loaded yet".
  static const MemberPage empty = MemberPage(members: [], hasMore: false);

  /// Where `list_members` resumes, or null when there is nothing to resume
  /// after.
  ///
  /// The sort is `(display_name, id)` and the cursor is both halves of it,
  /// because display names collide — a cursor of the name alone would skip
  /// everybody else who shares it.
  ({String name, String id})? get cursor => members.isEmpty
      ? null
      : (name: members.last.displayName, id: members.last.id);

  /// This page with [next] appended — how a list grows as somebody scrolls.
  ///
  /// [hasMore] comes from [next] alone: it is the newest thing known about the
  /// far end, and keeping our own would leave a list that had reached the
  /// bottom still claiming more.
  MemberPage followedBy(MemberPage next) =>
      MemberPage(members: itemsWith(next), hasMore: next.hasMore);
}
