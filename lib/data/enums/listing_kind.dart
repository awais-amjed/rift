/// Which directory a listing is in. Central moderates both the same way, so
/// its moderation calls take one of these rather than coming in pairs.
enum ListingKind {
  server,
  bot;

  static ListingKind fromString(String value) =>
      value == 'bot' ? ListingKind.bot : ListingKind.server;

  String toJson() => name;
}
