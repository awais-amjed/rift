import 'dart:async';

import 'package:nm/nm.dart';

import '../../data/enums/network_reading.dart';

/// NetworkManager's answer to "is this device on the internet", for
/// `NetworkCubit` on Linux.
///
/// connectivity_plus asks NetworkManager too, but counts only `none` as no
/// connection. NetworkManager says `none` only when nothing at all is up, and
/// a desktop nearly always has something: Tailscale's tunnel, or loopback,
/// which recent versions manage. With Wi-Fi off it says `limited` — on a
/// network, not on the internet. (Checked Oct 2 2026: Wi-Fi off gave state
/// "connected (local only)", connectivity `limited`.)
///
/// But `limited` only means NetworkManager's own check address did not
/// answer, and a Pi-hole, a VPN or that server being down gives the same on a
/// machine whose internet works (seen Oct 3 2026: "connected (site only)").
/// So it is [NetworkReading.unsure], and the cubit asks the servers you joined.
/// A captive portal and an unknown answer stay online: neither says the
/// internet is gone.
class LinuxConnectivity {
  const LinuxConnectivity._();

  static NetworkReading read(NetworkManagerConnectivityState state) =>
      switch (state) {
        NetworkManagerConnectivityState.none => NetworkReading.offline,
        NetworkManagerConnectivityState.limited => NetworkReading.unsure,
        _ => NetworkReading.online,
      };

  static Future<NetworkReading> check() async {
    final client = NetworkManagerClient();
    try {
      await client.connect();
      return read(client.connectivity);
    } finally {
      await client.close();
    }
  }

  /// Each change to NetworkManager's connectivity, for as long as it is
  /// listened to.
  static Stream<NetworkReading> changes() {
    final client = NetworkManagerClient();
    StreamSubscription<List<String>>? sub;
    late final StreamController<NetworkReading> controller;
    controller = StreamController(
      onListen: () async {
        try {
          await client.connect();
        } catch (e) {
          controller.addError(e);
          return;
        }
        sub = client.propertiesChanged.listen((names) {
          if (names.contains('Connectivity')) {
            controller.add(read(client.connectivity));
          }
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
