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
