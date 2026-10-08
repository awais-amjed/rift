import 'package:equatable/equatable.dart';

/// One round-trip reading for the call-quality graph.
class PingSample extends Equatable {
  final DateTime time;
  final double rttMs;

  const PingSample({required this.time, required this.rttMs});

  @override
  List<Object?> get props => [time, rttMs];
}
