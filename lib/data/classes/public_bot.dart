import 'bot_manifest.dart';

/// One row of the central bot directory — central's `public_bots` table.
///
/// The counterpart to `PublicServer`, and deliberately not the same shape. A
/// server listing carries an address and an invite: central hands out where to
/// go. A bot has no address — it runs wherever its author runs it — so a bot
/// listing is a catalogue entry, and the invite travels the other way, minted
/// on the admin's own server and handed to the program.
///
/// Everything here is plaintext and none of it is checked. [sourceUrl] is the
/// one line of provenance a stranger gets, which is why it is required: a bot
/// whose code nobody can read is a bot nobody should run.
class PublicBot {
  final String id;

  /// The central account that published it, which is not the bot's identity —
  /// a bot's identity is a keypair per server, and does not exist until it
  /// joins one.
  final String ownerId;

  final String name;
  final String? description;
  final String? iconPath;

  /// Where the code is. `https://…`, enforced by the column.
  final String sourceUrl;

  final List<String> tags;

  /// The author's copy of what a running instance publishes on `users.manifest`
  /// — the command list and the data-use sentence.
  ///
  /// Kept in the listing because the one moment somebody needs to know what a
  /// bot does with what it is handed is *before* installing it, and that is
  /// exactly when there is no instance to ask. Advertisement, like the
  /// manifest it mirrors: nothing here authorises anything.
  final BotManifest manifest;

  final bool isListed;

  /// The directory's only ranking signal. A like rather than a rating: an
  /// average needs volume before it means anything, and what a rating would
  /// really measure — does this bot work — is invisible to a database that
  /// never touches the server the bot runs on.
  final int likeCount;

  /// Whether *this* account has liked it. Not a column — read alongside the
  /// page from `bot_likes`, so the heart is filled in on first paint rather
  /// than after a second round trip.
  final bool likedByMe;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when a Rift moderator took the listing out of the directory, and
  /// read only by its owner — see `PublicServer.hiddenAt`.
  final DateTime? hiddenAt;
  final String? hiddenReason;

  /// The column's `length(description) <= 300`.
  static const maxDescription = 300;

  /// The column's `length(source_url) <= 200`.
  static const maxSourceUrl = 200;

  const PublicBot({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.iconPath,
    required this.sourceUrl,
    this.tags = const [],
    this.manifest = BotManifest.empty,
    this.isListed = true,
    this.likeCount = 0,
    this.likedByMe = false,
    required this.createdAt,
    required this.updatedAt,
    this.hiddenAt,
    this.hiddenReason,
  });

  bool get isHidden => hiddenAt != null;

  /// The host of [sourceUrl] — "github.com", "gitlab.com" — which is the part
  /// of the provenance a row has space for.
  ///
  /// Falls back to the whole string when there is no host to show. `Uri.parse`
  /// takes almost anything as a relative reference and hands back an *empty*
  /// host rather than failing, so a listing central somehow accepted without a
  /// scheme would otherwise draw a blank line where the provenance goes.
  String get sourceHost {
    final host = Uri.tryParse(sourceUrl)?.host ?? '';
    return host.isEmpty ? sourceUrl : host;
  }

  factory PublicBot.fromJson(
    Map<String, dynamic> json, {
    bool likedByMe = false,
  }) {
    return PublicBot(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      iconPath: json['icon_path'] as String?,
      sourceUrl: json['source_url'] as String,
      tags:
          (json['tags'] as List<dynamic>?)?.map((t) => t as String).toList() ??
          const [],
      manifest: BotManifest.fromJson(json['manifest'] as Map<String, dynamic>?),
      isListed: json['is_listed'] as bool? ?? true,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      likedByMe: likedByMe,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      hiddenAt: DateTime.tryParse(
        json['hidden_at'] as String? ?? '',
      )?.toLocal(),
      hiddenReason: json['hidden_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'name': name,
    'description': description,
    'icon_path': iconPath,
    'source_url': sourceUrl,
    'tags': tags,
    'manifest': manifest.toJson(),
    'is_listed': isListed,
    'like_count': likeCount,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'hidden_at': hiddenAt?.toUtc().toIso8601String(),
    'hidden_reason': hiddenReason,
  };

  /// Only the heart moves, so only the heart is here: a listing's own fields
  /// are changed by republishing it, which comes back as a fresh row.
  PublicBot copyWith({bool? likedByMe, int? likeCount}) => PublicBot(
    id: id,
    ownerId: ownerId,
    name: name,
    description: description,
    iconPath: iconPath,
    sourceUrl: sourceUrl,
    tags: tags,
    manifest: manifest,
    isListed: isListed,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
    createdAt: createdAt,
    updatedAt: updatedAt,
    hiddenAt: hiddenAt,
    hiddenReason: hiddenReason,
  );
}

/// How the browser orders the directory.
enum BotSort {
  /// Best-liked first — the default, and the reason `like_count` is a column.
  top,

  /// Newest first, which is the only way a bot with no likes yet is ever seen.
  fresh;

  /// The column central orders on, and the direction.
  String get column => switch (this) {
    BotSort.top => 'like_count',
    BotSort.fresh => 'created_at',
  };

  String get label => switch (this) {
    BotSort.top => 'Top',
    BotSort.fresh => 'New',
  };
}
