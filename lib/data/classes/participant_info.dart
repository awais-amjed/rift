class ParticipantInfo {
  final String identity;
  final String name;
  final bool isSpeaking;
  final bool isMicrophoneEnabled;
  final bool isCameraEnabled;
  final bool isLocal;

  const ParticipantInfo({
    required this.identity,
    required this.name,
    this.isSpeaking = false,
    this.isMicrophoneEnabled = false,
    this.isCameraEnabled = false,
    this.isLocal = false,
  });
}
