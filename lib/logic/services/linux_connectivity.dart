import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nm/nm.dart';

/// NetworkManager's answer to "is this device on the internet", for
/// `NetworkCubit` on Linux, in connectivity_plus's terms.
///
/// connectivity_plus asks NetworkManager too, but counts only `none` as no
/// connection. NetworkManager says `none` only when nothing at all is up, and
/// a desktop nearly always has something: Tailscale's tunnel, or loopback,
/// which recent versions manage. With Wi-Fi off it says `limited` — on a
/// network, not on the internet — which is what Windows' "No internet" globe
/// means, so it is offline here too. (Checked Oct 2 2026: Wi-Fi off gave
/// state "connected (local only)", connectivity `limited`.) A captive portal
/// and an unknown answer stay online: neither says the internet is gone.
class LinuxConnectivity {
  const LinuxConnectivity._();

  static bool isOffline(NetworkManagerConnectivityState state) =>
      state == NetworkManagerConnectivityState.none ||
      state == NetworkManagerConnectivityState.limited;

  static List<ConnectivityResult> _results(NetworkManagerClient client) =>
      isOffline(client.connectivity)
      ? const [ConnectivityResult.none]
      : const [ConnectivityResult.other];

  static Future<List<ConnectivityResult>> check() async {
    final client = NetworkManagerClient();
    try {
      await client.connect();
      return _results(client);
    } finally {
      await client.close();
    }
  }

  /// Each change to NetworkManager's connectivity, for as long as it is
  /// listened to.
  static Stream<List<ConnectivityResult>> changes() {
    final client = NetworkManagerClient();
    StreamSubscription<List<String>>? sub;
    late final StreamController<List<ConnectivityResult>> controller;
    controller = StreamController(
      onListen: () async {
        try {
          await client.connect();
        } catch (e) {
          controller.addError(e);
          return;
        }
        sub = client.propertiesChanged.listen((names) {
          if (names.contains('Connectivity')) controller.add(_results(client));
        });
      },
      onCancel: () async {
        await sub?.cancel();
        await client.close();
        await controller.close();
      },
    );
    return controller.stream;
  }
}
