import 'package:equatable/equatable.dart';

/// A page of things, and whether another one follows.
///
/// The two facts travel together or they drift apart: a "load more" wired to a
/// bare list has to guess, and guessing from a full page is the bug
/// [Paging.split] exists to avoid. Every paged read in the app answers in this
/// shape — the member roster, the friends tabs — so the shape is written once.
///
/// It carries no cursor. Where a page resumes depends on what is in it: the
/// roster resumes on `(display_name, id)` because display names collide, a
/// friends tab resumes on the handle alone because handles are unique. That
/// belongs on the subtype that knows.
class Paged<T> extends Equatable {
  final List<T> items;

  /// Whether another page follows — proved by the spare row the query
  /// over-fetched, never inferred from a page being full.
  final bool hasMore;

  const Paged({required this.items, required this.hasMore});

  /// A settled empty page: nothing in it, and nothing more coming. Distinct
  /// from null, which callers use for "not loaded yet".
  static const Paged<Never> empty = Paged<Never>(items: [], hasMore: false);

  bool get isEmpty => items.isEmpty;

  /// The items of this page followed by [next]'s — how a list grows as
  /// somebody scrolls.
  ///
  /// [hasMore] comes from [next] alone: it is the newest thing known about the
  /// far end, and keeping our own would leave a list that had reached the
  /// bottom still claiming more.
  List<T> itemsWith(Paged<T> next) => [...items, ...next.items];

  @override
  List<Object?> get props => [items, hasMore];
}
