import 'package:equatable/equatable.dart';

import '../../src/rust/api/screenshare/types.dart';

/// A program heard playing sound on Linux, kept so that a share can pick it
/// while it plays nothing: a paused player closes its stream, and a list of
/// streams alone left it out until it played again. Found again by its binary
/// and name, the way a share follows it.
class AudioAppHeard extends Equatable {
  final String binary;
  final String appName;

  /// What the desktop calls it, for matching a shared window to it.
  final String appId;

  const AudioAppHeard({
    required this.binary,
    required this.appName,
    required this.appId,
  });

  factory AudioAppHeard.of(AudioSource source) => AudioAppHeard(
    binary: source.binary,
    appName: source.appName,
    appId: source.appId,
  );

  factory AudioAppHeard.fromJson(Map<String, dynamic> json) => AudioAppHeard(
    binary: json['binary'] as String? ?? '',
    appName: json['appName'] as String? ?? '',
    appId: json['appId'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'binary': binary,
    'appName': appName,
    'appId': appId,
  };

  /// As the Rust library is handed it, and lists it while it plays nothing.
  AudioSource toSource() => AudioSource(
    index: 0,
    sink: 0,
    appName: appName,
    binary: binary,
    mediaName: '',
    appId: appId,
    playing: false,
  );

  /// The same program as [source].
  bool plays(AudioSource source) =>
      source.binary == binary && source.appName == appName;

  @override
  List<Object?> get props => [binary, appName, appId];
}
