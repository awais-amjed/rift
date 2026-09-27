/// Where the caller stands with one other member, as `dm_link_state` says.
///
/// [waiting] also covers the other side having ignored the request — the
/// server never tells a sender that, so neither can this.
enum DmLinkState {
  /// Nothing between the two of you yet.
  none,

  /// An ordinary conversation.
  open,

  /// You asked and they have not answered.
  waiting,

  /// They asked you.
  asked,

  /// They asked you and you put it away.
  ignored;

  /// Anything unknown reads as [open], so an older server — which has no
  /// requests at all — never locks a composer.
  static DmLinkState fromString(String? value) => DmLinkState.values.firstWhere(
    (s) => s.name == value,
    orElse: () => DmLinkState.open,
  );

  /// A request is waiting on this member's answer.
  bool get isRequestToMe => this == asked || this == ignored;
}
