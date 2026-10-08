import 'package:equatable/equatable.dart';

import '../enums/region_load_level.dart';

/// How busy one LiveKit region is, as `voice_roster` last reported it.
///
/// **A level, not a count.** The server works it out from forwarded streams
/// — an SFU copies rather than mixes, so the work is publishers × subscribers,
/// and twenty people listening to nobody is almost free — across every room
/// on the node, including ones this member cannot see. So what reaches the
/// client is only [RegionLoadLevel]: enough to choose a region, not enough to
/// tell that a hidden call has started.
///
/// Transient. It is a reading taken a few seconds ago, never persisted, and
/// absent until the first roster poll answers.
class RegionLoad extends Equatable {
  final String nodeId;
  final String label;

  /// Null when the region did not answer, or when an older server sent a
  /// shape this does not know.
  final RegionLoadLevel? level;

  /// False when the region did not answer at all, which is a different thing
  /// from being quiet and the one a manager most needs to see.
  final bool reachable;

  const RegionLoad({
    required this.nodeId,
    required this.label,
    this.level,
    this.reachable = true,
  });

  factory RegionLoad.fromJson(Map<String, dynamic> json) => RegionLoad(
    nodeId: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    level: RegionLoadLevel.tryParse(json['load']),
    reachable: json['reachable'] != false,
  );

  /// One line for a picker: how busy it is, or that it is offline.
  String? get summary {
    if (!reachable) return 'offline';
    return level?.label;
  }

  @override
  List<Object?> get props => [nodeId, label, level, reachable];
}
