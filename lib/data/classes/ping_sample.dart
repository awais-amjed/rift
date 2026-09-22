/// One round-trip reading for the call-quality graph.
class PingSample {
  final DateTime time;
  final double rttMs;

  const PingSample({required this.time, required this.rttMs});
}
