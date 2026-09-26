import '../enums/listing_kind.dart';

/// A server or bot listing as the moderation page shows it: what it says now,
/// who published it, and where it is hidden from.
///
/// One shape for both directories, because a moderator acts on either the
/// same way. [address] is the server's host or the bot's source — the part of
/// a listing its publisher cannot make up.
class ModerationListing {
  final ListingKind kind;
  final String id;

  /// What the directory colours this listing's fallback icon from — the
  /// server's id for a server, the listing's own for a bot — so a listing
  /// without a picture looks the same here as where it was reported.
  final String seed;
  final String name;
  final String? description;
  final String? iconPath;
  final String address;
  final bool isListed;
  final DateTime? hiddenAt;
  final String? hiddenReason;
  final String ownerId;
  final String ownerHandle;
  final bool ownerBanned;

  const ModerationListing({
    required this.kind,
    required this.id,
    required this.seed,
    required this.name,
    this.description,
    this.iconPath,
    required this.address,
    this.isListed = true,
    this.hiddenAt,
    this.hiddenReason,
    required this.ownerId,
    required this.ownerHandle,
    this.ownerBanned = false,
  });

  bool get isHidden => hiddenAt != null;

  /// The host alone, which is all a card has room for.
  String get host {
    final host = Uri.tryParse(address)?.host ?? '';
    return host.isEmpty ? address : host;
  }

  factory ModerationListing.fromJson(Map<String, dynamic> json) {
    return ModerationListing(
      kind: ListingKind.fromString(json['kind'] as String? ?? ''),
      id: json['id'] as String,
      seed: json['seed'] as String? ?? json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      iconPath: json['icon_path'] as String?,
      address: json['address'] as String? ?? '',
      isListed: json['is_listed'] as bool? ?? true,
      hiddenAt: DateTime.tryParse(
        json['hidden_at'] as String? ?? '',
      )?.toLocal(),
      hiddenReason: json['hidden_reason'] as String?,
      ownerId: json['owner_id'] as String? ?? '',
      ownerHandle: json['owner_handle'] as String? ?? '',
      ownerBanned: json['owner_banned'] as bool? ?? false,
    );
  }
}
