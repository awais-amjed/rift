/// Over the helper budget and one job: an operator's limits, each with the JSON
/// key, default and comment it needs.
///
/// The limits a self-hosted server's admin has set (`002_limits.sql`).
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
  /// `migrations/005_storage.sql` in the `rift-central` repo, which must agree.
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

  /// The DM override for [messageRetentionDays] (`002_limits.sql`). Null inherits
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

  /// How many people may be in one voice channel at once. [unlimited] is no
  /// cap.
  ///
  /// People, not connections: a screen share is a second connection held by
  /// somebody already counted. The server enforces this — `get_channel_token`
  /// refuses the next arrival — so the client never has to, and a client that
  /// ignored it would simply be refused a token.
  final int maxVoiceParticipants;

  /// The most a screen share may publish, in Mbps. [unlimited] is no cap.
  ///
  /// **This one the client has to keep**, and it is the only limit here that
  /// works that way. A LiveKit join token has nowhere to put a bitrate, so
  /// there is nothing for the server to clamp at the moment it hands one out,
  /// and nothing server-side throttles a publisher afterwards either. What
  /// the operator sets is a budget, and [shareMbps] is where it is applied.
  ///
  /// Deliberate rather than an oversight: this is a limit about cost, not
  /// about trust. The case it exists for is somebody left on the 10 Mbps
  /// default who has never been told what that costs everyone else.
  ///
  /// Why an operator would set it at all: a share goes out at full rate to
  /// every watcher with nothing downscaling in between, so one person at the
  /// 10 Mbps default costs 10 Mbps *per watcher* — a quarter of a gigabit at
  /// twenty-five of them (docs.joinrift.app/sizing/#calls).
  final int maxShareMbps;

  /// How many members the server holds. [unlimited] is no cap.
  ///
  /// Counts bots, which are members, and not banned members, who are not —
  /// a ban frees the seat. Enforced by `register_user`, inside the same
  /// transaction that spends the invite, so unlike the two above it is
  /// exact rather than approximate.
  final int maxMembers;

  /// How many bytes of attachments the server keeps. [unlimited] is no cap.
  ///
  /// Enforced by a trigger on the storage table, so it holds against
  /// whatever uploads. The client asks anyway — see [hasRoomFor] — because
  /// what Storage sends back when the trigger fires is an HTTP 500 with a
  /// Postgres error code in it, and somebody who has just picked a file
  /// deserves a sentence. Same division of labour as [allowsAttachment].
  final int maxStorageBytes;

  const ServerLimits({
    this.maxAttachmentBytes = defaultMaxAttachmentBytes,
    this.messageRetentionDays = unlimited,
    this.messageHistoryCap = unlimited,
    this.dmRetentionDays,
    this.dmHistoryCap,
    this.maxVoiceParticipants = unlimited,
    this.maxShareMbps = unlimited,
    this.maxMembers = unlimited,
    this.maxStorageBytes = unlimited,
  });

  /// True when [bytes] more will fit, given [used] already held.
  ///
  /// [used] comes from `storage_used` in the server's own details, so it is
  /// as fresh as the last time the server was opened. Stale by a little is
  /// the right trade: this exists to turn a failed upload into a sentence,
  /// and the trigger behind it is what actually decides.
  bool hasRoomFor(int bytes, {required int used}) =>
      maxStorageBytes == unlimited || used + bytes <= maxStorageBytes;

  /// What is left, or null when nothing is capped.
  int? remainingStorage(int used) => maxStorageBytes == unlimited
      ? null
      : (maxStorageBytes - used < 0 ? 0 : maxStorageBytes - used);

  /// What a screen share should actually publish, in Mbps: the smaller of
  /// what the sharer asked for and what the operator allows, and the sharer's
  /// own number when there is no cap.
  ///
  /// Mbps and not something finer because that is the only unit there is —
  /// the capture pipeline takes whole Mbps and refuses zero, so a cap stored
  /// in kbps would round on the way through and the number an operator typed
  /// would not be the number anything used.
  int shareMbps(int requested) => maxShareMbps == unlimited
      ? requested
      : (requested < maxShareMbps ? requested : maxShareMbps);

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
      maxVoiceParticipants: read('max_voice_participants', unlimited),
      maxShareMbps: read('max_share_mbps', unlimited),
      maxMembers: read('max_members', unlimited),
      maxStorageBytes: read('max_storage_bytes', unlimited),
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
    'max_voice_participants': maxVoiceParticipants,
    'max_share_mbps': maxShareMbps,
    'max_members': maxMembers,
    'max_storage_bytes': maxStorageBytes,
  };

  @override
  bool operator ==(Object other) =>
      other is ServerLimits &&
      other.maxAttachmentBytes == maxAttachmentBytes &&
      other.messageRetentionDays == messageRetentionDays &&
      other.messageHistoryCap == messageHistoryCap &&
      other.dmRetentionDays == dmRetentionDays &&
      other.dmHistoryCap == dmHistoryCap &&
      other.maxVoiceParticipants == maxVoiceParticipants &&
      other.maxShareMbps == maxShareMbps &&
      other.maxMembers == maxMembers &&
      other.maxStorageBytes == maxStorageBytes;

  @override
  int get hashCode => Object.hash(
    maxAttachmentBytes,
    messageRetentionDays,
    messageHistoryCap,
    dmRetentionDays,
    dmHistoryCap,
    maxVoiceParticipants,
    maxShareMbps,
    maxMembers,
    maxStorageBytes,
  );
}
