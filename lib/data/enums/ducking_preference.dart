/// What Windows does to other apps' sound while a call is open — the choice
/// in Windows' Sound window, Communications tab.
enum DuckingPreference {
  /// "Mute all other sounds".
  mute,

  /// "Reduce the volume of other sounds by 80%" — also what Windows does
  /// for someone who never opened that tab.
  lowerBy80,

  /// "Reduce the volume of other sounds by 50%".
  lowerBy50,

  /// "Do nothing".
  off;

  /// From the registry value `UserDuckingPreference`, as Windows stores it.
  static DuckingPreference fromRegistry(int value) => switch (value) {
    0 => mute,
    2 => lowerBy50,
    3 => off,
    _ => lowerBy80,
  };

  /// What it does to other apps, finishing "During calls, Windows …".
  String get effect => switch (this) {
    mute => 'mutes your other apps',
    lowerBy80 => 'turns your other apps down by 80%',
    lowerBy50 => 'turns your other apps down by 50%',
    off => 'leaves your other apps alone',
  };

  /// The option's words in Windows' own Sound window, so they can be found
  /// there.
  String get windowsLabel => switch (this) {
    mute => 'Mute all other sounds',
    lowerBy80 => 'Reduce the volume of other sounds by 80%',
    lowerBy50 => 'Reduce the volume of other sounds by 50%',
    off => 'Do nothing',
  };
}
