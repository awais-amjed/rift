import '../../data/classes/server_member.dart';

/// A set of chosen members, held as ids *and* as the rows behind them.
///
/// The ids are what gets saved; the rows are what gets drawn. Holding only the
/// ids was fine while the whole roster sat in memory — a row could always be
/// looked up in it. Now that the roster arrives a page at a time,
/// somebody already ticked may not be in the page on screen, and a picker
/// that could not draw them would silently drop them from the list of people it
/// is about to save.
///
/// Immutable, so a `setState` gets a new value rather than a mutated one, and
/// pure, so the "did this change?" rule that decides whether Save is enabled is
/// testable without a dialog.
class MemberSelection {
  final Set<String> ids;

  /// The rows behind [ids], in the order they were chosen. May be shorter than
  /// [ids] while a seeded selection is still resolving.
  final List<ServerMember> members;

  const MemberSelection({this.ids = const {}, this.members = const []});

  static const MemberSelection empty = MemberSelection();

  /// A selection of exactly [members], ids included — how a dialog seeds itself
  /// from a channel's existing membership.
  factory MemberSelection.of(Iterable<ServerMember> members) => MemberSelection(
    ids: {for (final member in members) member.id},
    members: List.of(members),
  );

  bool contains(String id) => ids.contains(id);

  /// This selection with [member] added if absent, removed if present.
  MemberSelection toggled(ServerMember member) => ids.contains(member.id)
      ? MemberSelection(
          ids: {...ids}..remove(member.id),
          members: [
            for (final held in members)
              if (held.id != member.id) held,
          ],
        )
      : MemberSelection(
          ids: {...ids, member.id},
          members: [...members, member],
        );

  /// Whether this holds a different set of people from [other].
  ///
  /// Compared as sets: ticking somebody and unticking them again is not a
  /// change, and a Save button that thought otherwise would offer to write what
  /// is already there.
  bool differsFrom(Set<String> other) =>
      ids.length != other.length || !ids.containsAll(other);
}

/// The rows a member picker pins above its browse, in the order they were
/// pinned. Only grows, so a tick or an untick never moves a row.
///
/// Whoever is in the selection before the first browse lands is pinned: the
/// people already in the channel, shown first. After that a new pick is pinned
/// only when the browse does not hold them (picked from a search), since a
/// pick from the browse is already on screen where it was clicked.
class MemberPins {
  final List<ServerMember> members;

  const MemberPins(this.members);

  static const MemberPins empty = MemberPins([]);

  /// These pins once [selection] is read; [browsed] is the browse's answer,
  /// null until it lands. The same value when nothing new is pinned.
  MemberPins after(
    MemberSelection selection, {
    required List<ServerMember>? browsed,
  }) {
    final pinned = {for (final member in members) member.id};
    final inBrowse = {for (final member in browsed ?? const []) member.id};
    final added = [
      for (final member in selection.members)
        if (!pinned.contains(member.id) && !inBrowse.contains(member.id))
          member,
    ];
    return added.isEmpty ? this : MemberPins([...members, ...added]);
  }

  /// The pinned rows, then [browse] less them.
  List<ServerMember> over(List<ServerMember> browse) {
    final pinned = {for (final member in members) member.id};
    return [
      ...members,
      for (final member in browse)
        if (!pinned.contains(member.id)) member,
    ];
  }
}
