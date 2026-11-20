/// How a directory browser orders its listings — the server and the bot
/// browser alike.
enum DirectorySort {
  /// Best-liked first — the default, and the reason `like_count` is a column.
  top,

  /// Newest first, which is the only way a listing with no likes yet is ever
  /// seen.
  fresh;

  /// The column central orders on, and the direction. Both directories have
  /// both columns, and an index for each order
  /// (`idx_public_bots_top`, `idx_public_servers_top`, and their `_new`).
  String get column => switch (this) {
    DirectorySort.top => 'like_count',
    DirectorySort.fresh => 'created_at',
  };

  String get label => switch (this) {
    DirectorySort.top => 'Top',
    DirectorySort.fresh => 'New',
  };
}
