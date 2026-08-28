/// Who put a message in a channel.
///
/// Everything here has been [member] since the app existed, and the type only
/// became necessary when something that is not a person learned to write a row
/// (migration 013). It is separate from *whether the body was encrypted* on
/// purpose: the two coincide today, and they stop coinciding as soon as bot
/// commands land, where a member sends a message in the clear.
enum MessageOrigin {
  /// A person, signed with their key. The only origin the app can verify.
  member,

  /// An incoming webhook — an outside service posting to a secret URL. Never
  /// signed, never encrypted, and never attributed to a person: `authorName`
  /// is the webhook's own name, frozen on the row when it posted.
  webhook,

  /// The server saying something about itself — a bot being handed this
  /// channel's key, or having it taken away (migration 028).
  ///
  /// Identical in shape to a webhook and different in the one way that
  /// matters: nothing outside the server is involved. Badging it WEBHOOK told
  /// people an integration somebody installed had posted, which is exactly the
  /// thing a badge exists to be honest about.
  system;

  /// Read from `origin_name`, never from `webhook_id`.
  ///
  /// `webhook_id` is nulled when the webhook is deleted (`ON DELETE SET NULL`)
  /// while the message stays — so keying off it would turn every message a
  /// removed integration ever posted back into a member's, under no name at
  /// all. `origin_name` is frozen on the row at insert for exactly this reason,
  /// and migration 013 constrains it to be present precisely when `sender_id`
  /// is not.
  /// `is_system` is its own column for the same reason `origin_name` is frozen:
  /// it cannot be inferred. A webhook's row keeps its origin after the webhook
  /// is deleted, so "no `webhook_id`" does not mean "not a webhook".
  static MessageOrigin fromRow(Map<String, dynamic> row) {
    if (row['origin_name'] == null) return MessageOrigin.member;
    return row['is_system'] == true
        ? MessageOrigin.system
        : MessageOrigin.webhook;
  }

  bool get isMember => this == MessageOrigin.member;
}
