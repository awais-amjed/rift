part of 'network_cubit.dart';

/// Whether this device has a network connection at all.
class NetworkState {
  /// No connection of any kind, by the platform's own account — on Windows,
  /// no adapter that Windows itself counts as connected to the internet — or
  /// a doubtful one that none of your servers answered either.
  final bool offline;

  const NetworkState({this.offline = false});
}
