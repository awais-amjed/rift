import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/linux_connectivity.dart';

part 'network_state.dart';

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Says when this device has no network, for the title bar to show.
///
/// The platform's answer, not a probe of ours: Rift reaches out to nobody but
/// the servers you joined, so it does not ping a third party to ask "is there
/// internet". Each platform already keeps that answer — Windows' is the one
/// behind the taskbar's "No internet" globe, which only counts an adapter
/// Windows found the internet through, so a VPN or a virtual switch with no
/// way out does not read as online. Linux's is NetworkManager's, read so that
/// it means the same (`LinuxConnectivity`).
///
/// It is about the device, never a server. A self-hosted server can sit on the
/// same network with no internet anywhere, and still work; whether a server
/// answers is a separate question.
class NetworkCubit extends Cubit<NetworkState> {
  /// How long the network has to stay gone before it is reported. Moving
  /// between networks drops everything for a moment, and a chip flashing up
  /// for that would be a false alarm; coming back is reported at once.
  static const settle = Duration(seconds: 2);

  final Duration _settle;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _pending;

  NetworkCubit({
    Stream<List<ConnectivityResult>>? changes,
    Future<List<ConnectivityResult>> Function()? check,
    Duration settle = settle,
  }) : _settle = settle,
       super(const NetworkState()) {
    if (changes == null || check == null) {
      if (!kIsWeb && Platform.isLinux) {
        changes = LinuxConnectivity.changes();
        check = LinuxConnectivity.check;
      } else {
        final connectivity = Connectivity();
        changes = connectivity.onConnectivityChanged;
        check = connectivity.checkConnectivity;
      }
    }
    // A platform that cannot say is not a reason to claim we're offline.
    _sub = changes.listen(_onChange, onError: (_) {});
    unawaited(check().then(_onChange, onError: (_) {}));
  }

  /// No connection at all: an empty answer, or nothing but `none`.
  static bool isOffline(List<ConnectivityResult> results) =>
      results.every((r) => r == ConnectivityResult.none);

  void _onChange(List<ConnectivityResult> results) {
    if (isClosed) return;
    if (!isOffline(results)) {
      _pending?.cancel();
      _pending = null;
      if (state.offline) emit(const NetworkState());
      return;
    }
    if (state.offline || _pending != null) return;
    _pending = Timer(_settle, () {
      _pending = null;
      if (!isClosed) emit(const NetworkState(offline: true));
    });
  }

  @override
  Future<void> close() async {
    _pending?.cancel();
    await _sub?.cancel();
    return super.close();
  }
}
