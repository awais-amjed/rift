/// Who Windows believes posts Rift's notifications, and which COM class it
/// asks to handle a press on one.
///
/// A press reaches Rift only through that class: Windows looks its CLSID up
/// under `HKCU\Software\Classes\CLSID\{guid}\LocalServer32` and either hands
/// the press to the running Rift that registered the class, or starts Rift
/// with [launchCommand] to deliver it (see `registerToastActivator`).
///
/// The release identity is the installer's app id. Every other storage
/// namespace (debug's `dev`, each `RIFT_PROFILE`) gets its own: one shared
/// class meant a press on profile A's notification went to whichever profile
/// had registered last.
class ToastIdentity {
  final String appName;
  final String appUserModelId;
  final String guid;

  const ToastIdentity._(this.appName, this.appUserModelId, this.guid);

  static const _releaseGuid = '919df387-f79b-5d74-bee3-b08f176b2a14';

  factory ToastIdentity.forSuffix(String suffix) {
    if (suffix.isEmpty) {
      return const ToastIdentity._('Rift', 'CodingFries.Rift', _releaseGuid);
    }
    return ToastIdentity._(
      'Rift ($suffix)',
      'CodingFries.Rift.$suffix',
      '${_releaseGuid.substring(0, 24)}${_fnv48(suffix)}',
    );
  }

  /// What Windows runs to deliver a press when Rift is not running. A profile
  /// named explicitly comes along as an argument: Windows passes no
  /// environment, so without it the press would open the default profile.
  static String launchCommand(String executable, {String? profile}) =>
      profile == null || profile.isEmpty
      ? '"$executable"'
      : '"$executable" --rift-profile=$profile';

  /// FNV-1a's step kept to 48 bits, as the GUID's last twelve hex digits:
  /// stable across runs and builds, which a registered class has to be.
  /// Native only — 48-bit products overflow a JavaScript number.
  static String _fnv48(String text) {
    const mask = 0xFFFFFFFFFFFF;
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & mask;
    }
    return hash.toRadixString(16).padLeft(12, '0');
  }
}
