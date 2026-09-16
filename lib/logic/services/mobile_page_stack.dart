import '../../data/enums/mobile_page.dart';

/// The pages open over a phone's list, bottom to top.
///
/// Kept apart from the widgets because the rules are the whole of the phone's
/// navigation and each is easy to get subtly wrong:
///
/// - **One conversation at a time.** Opening a chat replaces whatever
///   conversation was open rather than stacking on it, so back always lands on
///   the list or on the call, never on a trail of old conversations.
/// - **The call can sit under a conversation.** Opening a chat from inside a
///   call puts it above the call, and back returns to the call — which is
///   still going, whatever is on screen.
/// - **Reopening moves a page to the top** rather than adding a second copy.
///
/// Immutable: every change returns a new stack, so the shell can compare the
/// old and new to know what was dropped.
class MobilePageStack {
  final List<MobilePage> pages;

  const MobilePageStack([this.pages = const []]);

  MobilePage? get top => pages.isEmpty ? null : pages.last;

  bool contains(MobilePage page) => pages.contains(page);

  /// [page] on top, with any other conversation it replaces taken out.
  MobilePageStack opened(MobilePage page) => MobilePageStack([
    for (final p in pages)
      if (p != page && !(page.isConversation && p.isConversation)) p,
    page,
  ]);

  /// Without [page]. A stack that never had it is returned unchanged.
  MobilePageStack closed(MobilePage page) => contains(page)
      ? MobilePageStack([...pages.where((p) => p != page)])
      : this;

  /// The pages in this stack that [next] no longer has — the ones whose
  /// underlying state has to be closed to match.
  List<MobilePage> droppedBy(MobilePageStack next) => [
    for (final p in pages)
      if (!next.contains(p)) p,
  ];

  @override
  bool operator ==(Object other) =>
      other is MobilePageStack &&
      other.pages.length == pages.length &&
      Iterable.generate(pages.length).every((i) => other.pages[i] == pages[i]);

  @override
  int get hashCode => Object.hashAll(pages);
}
