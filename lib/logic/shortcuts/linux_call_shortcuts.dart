import '../../data/classes/call_shortcuts.dart';
import '../ptt/global_shortcuts_portal.dart';
import '../ptt/xdg_trigger.dart';
import 'call_shortcut_actions.dart';

// The call shortcuts as the Linux desktop knows them: ids, what to ask for,
// and what to keep of its answer. Asked for alongside push-to-talk by
// `LinuxGlobalShortcuts`, in one list.

/// The id the desktop knows [action] by.
String portalIdFor(CallShortcut action) => 'call-${action.name}';

CallShortcut? callShortcutForPortalId(String id) {
  for (final action in CallShortcut.values) {
    if (portalIdFor(action) == id) return action;
  }
  return null;
}

/// What to ask the desktop for: each action with keys, suggesting them.
List<PortalShortcut> portalShortcutsFor(CallShortcuts shortcuts) => [
  for (final action in CallShortcut.values)
    if (shortcuts[action] case final keys?)
      PortalShortcut(
        id: portalIdFor(action),
        description: callShortcutTitle(action),
        preferredTrigger: xdgTriggerForShortcut(keys),
      ),
];

/// The actions the desktop reported a key for.
Set<CallShortcut> deliveredActions(Map<String, String> triggers) => {
  for (final MapEntry(key: id, value: trigger) in triggers.entries)
    if (trigger.isNotEmpty) ?callShortcutForPortalId(id),
};

/// [stored] with each key the desktop reported in its place. A key Rift
/// cannot read, or none, leaves the stored one.
CallShortcuts adoptDesktopKeys(
  CallShortcuts stored,
  Map<String, String> triggers,
) {
  var adopted = stored;
  for (final MapEntry(key: id, value: trigger) in triggers.entries) {
    final action = callShortcutForPortalId(id);
    final keys = shortcutForTriggerDescription(trigger);
    if (action == null || keys == null || adopted[action] == keys) continue;
    adopted = adopted.withKeys(action, keys);
  }
  return adopted;
}
