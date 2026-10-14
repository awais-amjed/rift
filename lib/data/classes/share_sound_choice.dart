import 'package:equatable/equatable.dart';

import '../../src/rust/api/screenshare/types.dart';

/// The sound a window share of one app goes out with, kept when the user
/// ticks Remember: every app's but Rift's, or one app's. One app is found
/// again by its binary and name, never by its stream, which is a new one
/// each time it starts playing.
class ShareSoundChoice extends Equatable {
  /// Every app but Rift, rather than the one named.
  final bool allApps;
  final String binary;
  final String appName;

  const ShareSoundChoice.allApps() : allApps = true, binary = '', appName = '';

  const ShareSoundChoice.app({required this.binary, required this.appName})
    : allApps = false;

  /// [source] as a choice to keep; null is every app.
  factory ShareSoundChoice.of(AudioSource? source) => source == null
      ? const ShareSoundChoice.allApps()
      : ShareSoundChoice.app(binary: source.binary, appName: source.appName);

  factory ShareSoundChoice.fromJson(Map<String, dynamic> json) =>
      json['allApps'] as bool? ?? false
      ? const ShareSoundChoice.allApps()
      : ShareSoundChoice.app(
          binary: json['binary'] as String? ?? '',
          appName: json['appName'] as String? ?? '',
        );

  Map<String, dynamic> toJson() =>
      allApps ? {'allApps': true} : {'binary': binary, 'appName': appName};

  @override
  List<Object?> get props => [allApps, binary, appName];
}
