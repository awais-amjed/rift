import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/enums/network_reading.dart';
import '../../services/linux_connectivity.dart';

part 'network_state.dart';

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Says when this device has no network, for the title bar to show.
///
/// The platform's answer first: Rift reaches out to nobody but the servers you
/// joined, so it does not ping a third party to ask "is there internet". Each
/// platform already keeps that answer — Windows' is the one behind the
/// taskbar's "No internet" globe, which only counts an adapter Windows found
/// the internet through, so a VPN or a virtual switch with no way out does not
/// read as online. Linux's is NetworkManager's (`LinuxConnectivity`).
///
/// When the platform is [NetworkReading.unsure], [confirm] asks the servers
/// you joined, and one answering is enough: a false "No internet" on a machine
/// that is plainly online is worse than none. With no server to ask, the
/// platform's doubt stands.
///
/// It is about the device, never a server. A self-hosted server can sit on the
/// same network with no internet anywhere, and still work; whether a server
/// answers is a separate question.
class NetworkCubit extends Cubit<NetworkState> {
  /// How long the network has to stay gone before it is reported. Moving
  /// between networks drops everything for a moment, and a chip flashing up
  /// for that would be a false alarm; coming back is reported at once.
  static const settle = Duration(seconds: 2);

  /// How often a doubtful reading is asked about again while the chip shows.
  /// The platform may not say anything new for minutes — NetworkManager
  /// re-checks every five — and the servers coming back is the news.
  static const recheck = Duration(seconds: 30);

  final Duration _settle;
  final Duration _recheck;
  final Future<bool?> Function()? _confirm;
  StreamSubscription<NetworkReading>? _sub;
  Timer? _pending;
  Timer? _again;

  /// The platform's latest reading, so an answer from [_confirm] that arrives
  /// after the platform has changed its mind is dropped.
  NetworkReading _latest = NetworkReading.online;

  NetworkCubit({
    Stream<NetworkReading>? changes,
    Future<NetworkReading> Function()? check,
    Future<bool?> Function()? confirm,
    Duration settle = settle,
    Duration recheck = recheck,
  }) : _settle = settle,
       _recheck = recheck,
       _confirm = confirm,
       super(const NetworkState()) {
    if (changes == null || check == null) {
      if (!kIsWeb && Platform.isLinux) {
        changes = LinuxConnectivity.changes();
        check = LinuxConnectivity.check;
      } else {
        final connectivity = Connectivity();
        changes = connectivity.onConnectivityChanged.map(reading);
        check = () => connectivity.checkConnectivity().then(reading);
      }
    }
    // A platform that cannot say is not a reason to claim we're offline.
    _sub = changes.listen(_onReading, onError: (_) {});
    unawaited(check().then(_onReading, onError: (_) {}));
  }

  /// connectivity_plus's answer: no connection at all is an empty list, or
  /// nothing but `none`.
  static NetworkReading reading(List<ConnectivityResult> results) =>
      results.every((r) => r == ConnectivityResult.none)
      ? NetworkReading.offline
      : NetworkReading.online;

  void _onReading(NetworkReading reading) {
    if (isClosed) return;
    _latest = reading;
    _again?.cancel();
    _again = null;
    switch (reading) {
      case NetworkReading.online:
        _online();
      case NetworkReading.offline:
        _offline();
      case NetworkReading.unsure:
        unawaited(_ask());
    }
  }

  Future<void> _ask() async {
    final confirm = _confirm;
    final reached = confirm == null
        ? null
        : await confirm().catchError((_) => null);
    if (isClosed || _latest != NetworkReading.unsure) return;
    if (reached ?? false) return _online();
    _offline();
    // Only when there was somebody to ask: with nobody, nothing can change
    // until the platform does.
    if (reached != null) _again = Timer(_recheck, () => unawaited(_ask()));
  }

  void _online() {
    _pending?.cancel();
    _pending = null;
    if (state.offline) emit(const NetworkState());
  }

  void _offline() {
    if (state.offline || _pending != null) return;
    _pending = Timer(_settle, () {
      _pending = null;
      if (!isClosed) emit(const NetworkState(offline: true));
    });
  }

  @override
  Future<void> close() async {
    _pending?.cancel();
    _again?.cancel();
    await _sub?.cancel();
    return super.close();
  }
}
