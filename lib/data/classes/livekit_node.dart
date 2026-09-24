/// One LiveKit a server may hold a call on.
///
/// A server starts with one — the `is_default` mirror of its `livekit_url` —
/// and an operator may add more so that a call is held near the people in it.
/// The label is theirs to write: only they know whether the box in Frankfurt
/// is "Europe" or "Main".
///
/// **A call lives on exactly one node.** LiveKit's open-source server binds a
/// room to a single node and cross-node media is a Cloud feature, so this is
/// never "each person connects to their nearest". It is one decision, made
/// when the room is created, and everybody who joins afterwards goes where it
/// already is — see `app.claim_voice_node` in the self-host schema.
class LiveKitNode {
  final String id;

  /// What a channel manager picks and a member is shown. A place, not a host.
  final String label;

  /// `wss://` or `ws://`. Also what the latency probe measures against.
  final String url;

  /// The one mirroring `servers.livekit_url`, which every server has and
  /// nobody can delete.
  final bool isDefault;

  const LiveKitNode({
    required this.id,
    required this.label,
    required this.url,
    this.isDefault = false,
  });

  factory LiveKitNode.fromJson(Map<String, dynamic> json) => LiveKitNode(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    url: json['url'] as String? ?? '',
    isDefault: json['is_default'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'url': url,
    'is_default': isDefault,
  };

  @override
  bool operator ==(Object other) =>
      other is LiveKitNode &&
      other.id == id &&
      other.label == label &&
      other.url == url &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(id, label, url, isDefault);
}
