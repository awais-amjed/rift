import 'package:equatable/equatable.dart';

/// A clip of a call kept on this device (`ClipLibrary`): what the list of
/// recent clips shows, without the sound, which is opened only when the clip
/// is.
class StoredClip extends Equatable {
  /// Its name on the disk, which orders the clips: the time it was clipped,
  /// in microseconds, made unique.
  final String id;

  /// When the shortcut was pressed.
  final DateTime at;
  final int rate;
  final int channels;
  final int frames;

  /// The call's server and channel, as they were when it was clipped: what
  /// Add to soundboard is offered for. Null for a DM call's channel.
  final String? serverId;
  final String? channelId;

  /// Where it was clipped, in words, as it was then: "General · Rift Test".
  final String place;

  /// A DM call has no soundboard, whatever server it is on.
  final bool fromDmCall;

  const StoredClip({
    required this.id,
    required this.at,
    required this.rate,
    required this.channels,
    required this.frames,
    required this.serverId,
    required this.channelId,
    required this.place,
    required this.fromDmCall,
  });

  Duration get duration =>
      Duration(microseconds: rate == 0 ? 0 : frames * 1000000 ~/ rate);

  factory StoredClip.fromJson(Map<String, dynamic> json) => StoredClip(
    id: json['id'] as String,
    at: DateTime.fromMicrosecondsSinceEpoch(json['at'] as int, isUtc: true),
    rate: json['rate'] as int,
    channels: json['channels'] as int,
    frames: json['frames'] as int,
    serverId: json['server_id'] as String?,
    channelId: json['channel_id'] as String?,
    place: json['place'] as String,
    fromDmCall: json['from_dm_call'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toUtc().microsecondsSinceEpoch,
    'rate': rate,
    'channels': channels,
    'frames': frames,
    'server_id': serverId,
    'channel_id': channelId,
    'place': place,
    'from_dm_call': fromDmCall,
  };

  @override
  List<Object?> get props => [
    id,
    at,
    rate,
    channels,
    frames,
    serverId,
    channelId,
    place,
    fromDmCall,
  ];
}
