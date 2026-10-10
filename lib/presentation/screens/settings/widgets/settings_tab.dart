/// The settings screen's tabs, in the order the sidebar lists them.
enum SettingsTab { appearance, general, voiceAndAudio, backup }

/// What each tab is called.
///
/// On the enum because three places name these — the desktop sidebar, the
/// phone's list, and the header above the contents — and they had drifted:
/// the last tab was "Cloud backup" on a desktop and "Backup & recovery key"
/// on a phone, while five screens elsewhere told people to find it under
/// "Settings → Account". It is where you sign in, so that is what it is
/// called, and there is now one place to say so.
extension SettingsTabLabel on SettingsTab {
  String get label => switch (this) {
    SettingsTab.appearance => 'Appearance',
    SettingsTab.general => 'General',
    SettingsTab.voiceAndAudio => 'Voice & audio',
    SettingsTab.backup => 'Account & backup',
  };
}

/// A place in Settings to open at: a tab, and optionally one section in it
/// to scroll to and light up — for a notice whose "Fix it" leads there.
class SettingsTarget {
  final SettingsTab tab;
  final SettingsSection? section;

  const SettingsTarget(this.tab, {this.section});
}

/// Sections something outside Settings can point at.
enum SettingsSection {
  /// Voice & audio's "Other apps' volume during calls".
  ducking,
}
