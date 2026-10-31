part of 'audio_device_list_cubit.dart';

/// The input and output devices on offer, and what is known about them.
class AudioDeviceLists extends Equatable {
  final List<MediaDevice> inputs;
  final List<MediaDevice> outputs;

  /// Whether the lists are WebRTC's, so a pick can be applied now. When WebRTC
  /// lists nothing they are the system's and a pick is only saved — see
  /// [AudioDevices.choices].
  final bool live;

  /// What Windows reports each endpoint's shared format as, keyed by device
  /// id. Empty means nothing is known, and nothing is then refused on its
  /// account.
  final Map<String, AudioEndpoint> inputFormats;
  final Map<String, AudioEndpoint> outputFormats;

  /// Whether the lists have been read at all since Rift started.
  final bool loaded;

  /// Why the last read failed. The lists from the read before it stay.
  final String? loadError;

  const AudioDeviceLists({
    this.inputs = const [],
    this.outputs = const [],
    this.live = false,
    this.inputFormats = const {},
    this.outputFormats = const {},
    this.loaded = false,
    this.loadError,
  });

  AudioDeviceLists copyWith({
    List<MediaDevice>? inputs,
    List<MediaDevice>? outputs,
    bool? live,
    Map<String, AudioEndpoint>? inputFormats,
    Map<String, AudioEndpoint>? outputFormats,
    bool? loaded,
    String? loadError,
    bool clearLoadError = false,
  }) => AudioDeviceLists(
    inputs: inputs ?? this.inputs,
    outputs: outputs ?? this.outputs,
    live: live ?? this.live,
    inputFormats: inputFormats ?? this.inputFormats,
    outputFormats: outputFormats ?? this.outputFormats,
    loaded: loaded ?? this.loaded,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
  );

  @override
  List<Object?> get props => [
    inputs,
    outputs,
    live,
    inputFormats,
    outputFormats,
    loaded,
    loadError,
  ];
}
