/// Who may start a DM with a member on one server (`users.dm_policy`).
///
/// Only a *first* message asks. Somebody already talked to is never affected
/// by changing it, which is what makes turning it up safe.
enum DmPolicy {
  everyone,
  requests,
  nobody;

  /// Anything unknown reads as [everyone], the server's own default.
  static DmPolicy fromString(String? value) => DmPolicy.values.firstWhere(
    (p) => p.name == value,
    orElse: () => DmPolicy.everyone,
  );

  String toJson() => name;

  String get label => switch (this) {
    DmPolicy.everyone => 'Everyone',
    DmPolicy.requests => 'Ask me first',
    DmPolicy.nobody => 'No one new',
  };

  String get description => switch (this) {
    DmPolicy.everyone => 'Anyone on this server can message you.',
    DmPolicy.requests =>
      'A first message from someone new waits in Requests until you accept '
          'it. It doesn\'t notify you.',
    DmPolicy.nobody =>
      'Only people you already have a conversation with can message you.',
  };
}
