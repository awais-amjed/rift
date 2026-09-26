/// An account a moderator stopped from publishing to the directory.
class PublisherBan {
  final String userId;
  final String handle;
  final DateTime createdAt;
  final String? reason;
  final String? bannedByHandle;

  const PublisherBan({
    required this.userId,
    required this.handle,
    required this.createdAt,
    this.reason,
    this.bannedByHandle,
  });

  factory PublisherBan.fromJson(Map<String, dynamic> json) {
    return PublisherBan(
      userId: json['user_id'] as String,
      handle: json['handle'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      reason: json['reason'] as String?,
      bannedByHandle: json['banned_by_handle'] as String?,
    );
  }
}
