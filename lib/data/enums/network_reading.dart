/// What the platform says about this device's way out to the internet.
///
/// Three answers, not two, because Linux has a third: NetworkManager's
/// `limited` means "on a network, but my check address did not answer" — which
/// is Wi-Fi off with Tailscale still up, and is also a Pi-hole or a VPN
/// blocking that one address on a machine whose internet works.
enum NetworkReading {
  online,
  offline,

  /// The platform is not sure. `NetworkCubit` asks the servers you joined
  /// before it says anything.
  unsure,
}
