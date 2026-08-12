/// The limits a self-hosted server's admin has set (migration 007).
///
/// Central imposes its limits because central pays for central; a self-hosted
/// server imposes whatever its operator decides, which is usually nothing. So
/// **every count-based limit here defaults to [unlimited]**, and [defaults] is
/// what a server that predates this feature — or one whose admin never opened
/// the dialog — reports.
///
/// What is deliberately absent is a daily message quota. A quota is a rate
/// limit, not a storage bound: N messages a day, forever, is still unbounded.
/// What an operator is actually worried about is the disk, and the instruments
/// for that are a ceiling on kept history and a ceiling on file size.
///
/// [maxAttachmentBytes] is the one limit with no "off", because it is a size
/// rather than a count: storage has always had a ceiling, and
/// [defaultMaxAttachmentBytes] is the one it already had.
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

  /// Server-wide default: delete messages older than this many days.
  /// [unlimited] keeps everything. A channel may override it — see
  /// [Channel.retentionDays].
  final int messageRetentionDays;

  /// Server-wide default: keep at most this many messages per channel and per
  /// DM pair. [unlimited] means no cap. A channel may override it — see
  /// [Channel.historyCap].
  final int messageHistoryCap;

  /// The DM override for [messageRetentionDays] (migration 009). Null inherits
  /// it; [unlimited] keeps DMs while channels are still being swept.
  ///
  /// Nullable where the two above are not, for the same reason
  /// [Channel.retentionDays] is: those set the base case, this overrides it,
  /// and "inherit" is a different answer from "no limit".
  final int? dmRetentionDays;

  /// The DM override for [messageHistoryCap]. Null inherits it. It counts a
  /// conversation rather than a sender — both people's messages together, the
  /// same bucket seen from either side.
  ///
  /// There is no per-conversation setting and won't be: a DM belongs to two
  /// people, so neither end is the right person to decide how long the other's
  /// messages survive.
  final int? dmHistoryCap;

  const ServerLimits({
    this.maxAttachmentBytes = defaultMaxAttachmentBytes,
    this.messageRetentionDays = unlimited,
    this.messageHistoryCap = unlimited,
    this.dmRetentionDays,
    this.dmHistoryCap,
  });

  /// What DMs are actually swept by, inherit resolved.
  int get effectiveDmRetentionDays => dmRetentionDays ?? messageRetentionDays;

  /// What DM conversations are actually capped at, inherit resolved.
  int get effectiveDmHistoryCap => dmHistoryCap ?? messageHistoryCap;

  /// What a server reports before an admin has set anything.
  static const ServerLimits defaults = ServerLimits();

  /// True when [bytes] is small enough to upload here.
  ///
  /// The client asks so the user gets a sentence instead of a failed upload;
  /// the bucket's own `file_size_limit` is what actually enforces it, and
  /// `update_server` keeps the two in step.
  bool allowsAttachment(int bytes) => bytes <= maxAttachmentBytes;

  /// True when the operator has asked for anything at all to be swept —
  /// including a server that keeps its channels forever and trims only DMs.
  bool get sweepsHistory =>
      messageRetentionDays != unlimited ||
      messageHistoryCap != unlimited ||
      effectiveDmRetentionDays != unlimited ||
      effectiveDmHistoryCap != unlimited;

  /// Reads the snake_case shape both `servers` rows and `update_server`
  /// responses use. Any field the server didn't send falls back to its
  /// default, so an older server missing these columns still parses.
  factory ServerLimits.fromJson(Map<String, dynamic> json) {
    int read(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    // Distinct from [read]: here a missing or null key *is* the answer, so
    // there is no fallback to fall back to.
    int? readNullable(String key) {
      final value = json[key];
      return value is num ? value.toInt() : null;
    }

    return ServerLimits(
      maxAttachmentBytes: read(
        'max_attachment_bytes',
        defaultMaxAttachmentBytes,
      ),
      messageRetentionDays: read('message_retention_days', unlimited),
      messageHistoryCap: read('message_history_cap', unlimited),
      dmRetentionDays: readNullable('dm_retention_days'),
      dmHistoryCap: readNullable('dm_history_cap'),
    );
  }

  /// Every field, nulls included. Callers send the whole object, so an omitted
  /// key would read as "leave it alone" where an explicit null means "go back
  /// to inheriting" — and those must not be the same request.
  Map<String, dynamic> toJson() => {
    'max_attachment_bytes': maxAttachmentBytes,
    'message_retention_days': messageRetentionDays,
    'message_history_cap': messageHistoryCap,
    'dm_retention_days': dmRetentionDays,
    'dm_history_cap': dmHistoryCap,
  };

  @override
  bool operator ==(Object other) =>
      other is ServerLimits &&
      other.maxAttachmentBytes == maxAttachmentBytes &&
      other.messageRetentionDays == messageRetentionDays &&
      other.messageHistoryCap == messageHistoryCap &&
      other.dmRetentionDays == dmRetentionDays &&
      other.dmHistoryCap == dmHistoryCap;

  @override
  int get hashCode => Object.hash(
    maxAttachmentBytes,
    messageRetentionDays,
    messageHistoryCap,
    dmRetentionDays,
    dmHistoryCap,
  );
}
