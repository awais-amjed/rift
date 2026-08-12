/// The limits a self-hosted server's admin has set (migration 007).
///
/// Central imposes its limits because central pays for central; a self-hosted
/// server imposes whatever its operator decides, which is usually nothing. So
/// **every quota here defaults to [unlimited]**, and [defaults] is what a server
/// that predates this feature — or one whose admin never opened the dialog —
/// reports.
///
/// The one exception is [maxAttachmentBytes], which is a size rather than a
/// count and therefore has no meaningful "off": storage has always had a
/// ceiling, and [defaultMaxAttachmentBytes] is the one it already had.
class ServerLimits {
  /// The value every count-based limit uses to mean "no limit".
  static const int unlimited = 0;

  /// The `chat-attachments` bucket's original hardcoded cap, now the default
  /// for the column that replaced it — so upgrading changes nothing.
  static const int defaultMaxAttachmentBytes = 26214400; // 25 MB

  /// Storage refuses an object past this, so a cap beyond it cannot be met.
  static const int maxAttachmentCeiling = 524288000; // 500 MB

  /// The central tier's per-file cap. Not an operator setting and never will
  /// be — central pays for central's storage, so this is fixed here and in
  /// `central_server_migrations/005_storage.sql`, which must agree.
  static const int centralMaxAttachmentBytes = 10485760; // 10 MB

  /// Per-file attachment cap in bytes.
  final int maxAttachmentBytes;

  /// Messages per member per rolling 24h in a channel that sets no quota of
  /// its own. See [Channel.dailyQuota] for the per-channel override.
  final int defaultChannelDailyQuota;

  /// Messages per member per rolling 24h across all of their server DMs — the
  /// same shape as the central tier's daily quota.
  final int dmDailyQuota;

  /// Delete messages older than this many days. [unlimited] keeps everything.
  final int messageRetentionDays;

  /// Keep at most this many messages per channel and per DM pair.
  final int messageHistoryCap;

  const ServerLimits({
    this.maxAttachmentBytes = defaultMaxAttachmentBytes,
    this.defaultChannelDailyQuota = unlimited,
    this.dmDailyQuota = unlimited,
    this.messageRetentionDays = unlimited,
    this.messageHistoryCap = unlimited,
  });

  /// What a server reports before an admin has set anything.
  static const ServerLimits defaults = ServerLimits();

  /// True when [bytes] is small enough to upload here.
  ///
  /// The client asks so the user gets a sentence instead of a failed upload;
  /// the bucket's own `file_size_limit` is what actually enforces it, and
  /// `update_server` keeps the two in step.
  bool allowsAttachment(int bytes) => bytes <= maxAttachmentBytes;

  /// True when the operator has asked for anything at all to be swept.
  bool get sweepsHistory =>
      messageRetentionDays != unlimited || messageHistoryCap != unlimited;

  /// Reads the snake_case shape both `servers` rows and `update_server`
  /// responses use. Any field the server didn't send falls back to its
  /// default, so an older server missing these columns still parses.
  factory ServerLimits.fromJson(Map<String, dynamic> json) {
    int read(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    return ServerLimits(
      maxAttachmentBytes: read(
        'max_attachment_bytes',
        defaultMaxAttachmentBytes,
      ),
      defaultChannelDailyQuota: read('default_channel_daily_quota', unlimited),
      dmDailyQuota: read('dm_daily_quota', unlimited),
      messageRetentionDays: read('message_retention_days', unlimited),
      messageHistoryCap: read('message_history_cap', unlimited),
    );
  }

  Map<String, dynamic> toJson() => {
    'max_attachment_bytes': maxAttachmentBytes,
    'default_channel_daily_quota': defaultChannelDailyQuota,
    'dm_daily_quota': dmDailyQuota,
    'message_retention_days': messageRetentionDays,
    'message_history_cap': messageHistoryCap,
  };

  ServerLimits copyWith({
    int? maxAttachmentBytes,
    int? defaultChannelDailyQuota,
    int? dmDailyQuota,
    int? messageRetentionDays,
    int? messageHistoryCap,
  }) => ServerLimits(
    maxAttachmentBytes: maxAttachmentBytes ?? this.maxAttachmentBytes,
    defaultChannelDailyQuota:
        defaultChannelDailyQuota ?? this.defaultChannelDailyQuota,
    dmDailyQuota: dmDailyQuota ?? this.dmDailyQuota,
    messageRetentionDays: messageRetentionDays ?? this.messageRetentionDays,
    messageHistoryCap: messageHistoryCap ?? this.messageHistoryCap,
  );

  @override
  bool operator ==(Object other) =>
      other is ServerLimits &&
      other.maxAttachmentBytes == maxAttachmentBytes &&
      other.defaultChannelDailyQuota == defaultChannelDailyQuota &&
      other.dmDailyQuota == dmDailyQuota &&
      other.messageRetentionDays == messageRetentionDays &&
      other.messageHistoryCap == messageHistoryCap;

  @override
  int get hashCode => Object.hash(
    maxAttachmentBytes,
    defaultChannelDailyQuota,
    dmDailyQuota,
    messageRetentionDays,
    messageHistoryCap,
  );
}
