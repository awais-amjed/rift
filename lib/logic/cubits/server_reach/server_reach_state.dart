part of 'server_reach_cubit.dart';

/// Whether the selected server can be reached.
class ServerReachState extends Equatable {
  /// The selected server's name while it has been out of reach for longer
  /// than a reconnect takes; null while it answers, or nothing is selected.
  final String? unreachableName;

  const ServerReachState({this.unreachableName});

  @override
  List<Object?> get props => [unreachableName];
}
