/// How busy one LiveKit region is, as `voice_roster` last reported it.
///
/// **Streams, not people, is the number that means anything.** An SFU copies
/// rather than mixes, so the work is publishers × subscribers: twenty people
/// listening to nobody is almost free, and six people with one screen share
/// between them is not. A head count would call the first busy and the second
/// idle, which is backwards — see the measurements behind
/// `docs.joinrift.app/sizing/#calls`.
///
/// Transient. It is a reading taken a few seconds ago, never persisted, and
/// absent until the first roster poll answers.
class RegionLoad {
  final String nodeId;
  final String label;

  /// Rooms with somebody in them.
  final int calls;
  final int people;

  /// How many of those people are sending anything — voice, camera or screen.
  final int publishers;

  /// publishers × everybody else in their room, summed. The forwarding cost.
  final int streams;

  /// False when the region did not answer at all, which is a different thing
  /// from being idle and the one a manager most needs to see.
  final bool reachable;

  const RegionLoad({
    required this.nodeId,
    required this.label,
    this.calls = 0,
    this.people = 0,
    this.publishers = 0,
    this.streams = 0,
    this.reachable = true,
  });

  factory RegionLoad.fromJson(Map<String, dynamic> json) => RegionLoad(
    nodeId: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    calls: (json['calls'] as num?)?.toInt() ?? 0,
    people: (json['people'] as num?)?.toInt() ?? 0,
    publishers: (json['publishers'] as num?)?.toInt() ?? 0,
    streams: (json['streams'] as num?)?.toInt() ?? 0,
    reachable: json['reachable'] != false,
  );

  /// Nothing happening here at all.
  bool get isIdle => reachable && people == 0;

  /// One line for a picker: what is going on, shortest true form.
  String get summary {
    if (!reachable) return 'not answering';
    if (people == 0) return 'idle';
    final who = people == 1 ? '1 person' : '$people people';
    return calls <= 1 ? who : '$who in $calls calls';
  }
}
