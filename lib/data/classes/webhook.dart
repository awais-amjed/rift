/// One incoming webhook: a secret URL an outside service posts to, which lands
/// in a channel as an unencrypted message (`004_webhooks.sql`, BOTS.md §7).
///
/// **The secret is not here, and cannot be.** It is stored hashed and returned
/// exactly once, by `create_webhook`, at the moment it is minted — see
/// [WebhookSecret]. Everything on this class is what a channel manager may read
/// back afterwards: what it is called, where it posts, and whether it is still
/// being used.
class Webhook {
  final String id;
  final String channelId;
  final String name;
  final DateTime createdAt;

  /// When it last posted, or null if it never has.
  ///
  /// The point of showing it is the integration that quietly stopped working
  /// months ago: nothing else on the server will ever mention it, and a
  /// credential nobody is using is one to revoke.
  final DateTime? lastUsedAt;

  const Webhook({
    required this.id,
    required this.channelId,
    required this.name,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory Webhook.fromJson(Map<String, dynamic> json) => Webhook(
    id: json['id'] as String,
    channelId: json['channel_id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    lastUsedAt: DateTime.tryParse('${json['last_used_at']}'),
  );
}

/// A freshly minted webhook, with the one and only copy of its secret.
///
/// Separate from [Webhook] so the secret cannot be carried around by accident:
/// nothing stores one of these, and the dialog that receives it holds it only
/// until it is closed. Losing it means deleting the webhook and making another,
/// which is the correct trade — a secret the server could show you twice is a
/// secret the server is keeping.
class WebhookSecret {
  final String id;

  /// The full URL to post to, assembled from the server's own address.
  final String url;

  const WebhookSecret({required this.id, required this.url});
}
