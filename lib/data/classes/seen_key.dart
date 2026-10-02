/// The chat key this device last saw for one person, and when it saw it
/// change — kept so a key that changes is said out loud in the conversation,
/// not only in a profile somebody has to think to open.
///
/// Trust on first sight: the first key seen is the baseline and says nothing.
/// That is weaker than a safety code, and it is not meant to replace one —
/// it catches the change that happens *later*, which is when an interception
/// would start and when nobody is looking.
///
/// This device's record alone, like `AppState.verifiedCodes`: it holds public
/// keys, nothing secret, and it is never uploaded.
class SeenKey {
  /// How many changes are remembered. Each one is a line in the
  /// conversation; a person who changes key more often than this has made
  /// the point already.
  static const maxChanges = 10;

  /// Their chat public key, base64, as last seen.
  final String key;

  /// When this device noticed each change, oldest first.
  final List<DateTime> changes;

  /// Whether the newest change has been looked at — the safety code opened
  /// and closed, or the new code marked as matching. Until then the DM header
  /// says the key changed.
  final bool acknowledged;

  const SeenKey({
    required this.key,
    this.changes = const [],
    this.acknowledged = true,
  });

  /// Whether there is a change nobody has looked at yet.
  bool get unacknowledgedChange => changes.isNotEmpty && !acknowledged;

  /// The record after seeing [seen] at [at]: unchanged for the same key,
  /// a new baseline for the first one, a change otherwise.
  static SeenKey noting(SeenKey? before, String seen, DateTime at) {
    if (before == null) return SeenKey(key: seen);
    if (before.key == seen) return before;
    final changes = [...before.changes, at];
    return SeenKey(
      key: seen,
      changes: changes.length > maxChanges
          ? changes.sublist(changes.length - maxChanges)
          : changes,
      acknowledged: false,
    );
  }

  SeenKey acknowledge() =>
      SeenKey(key: key, changes: changes, acknowledged: true);

  factory SeenKey.fromJson(Map<String, dynamic> json) {
    return SeenKey(
      key: json['key'] as String,
      changes: [
        for (final at in json['changes'] as List<dynamic>? ?? const [])
          DateTime.parse(at as String),
      ],
      acknowledged: json['acknowledged'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'changes': [for (final at in changes) at.toUtc().toIso8601String()],
    'acknowledged': acknowledged,
  };
}
