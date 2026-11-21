import '../../data/classes/call_shortcuts.dart';
import '../cubits/livekit/livekit_cubit.dart';

/// What a call shortcut does, wherever the press came from: the window, the
/// Windows hook or the Linux desktop. Each is the button's own action.
void runCallShortcut(CallShortcut action, LiveKitCubit livekit) {
  switch (action) {
    case CallShortcut.mute:
      livekit.toggleMicrophone();
    case CallShortcut.deafen:
      livekit.toggleDeafen();
    case CallShortcut.leave:
      // Outside a call there is nothing to leave, and leaving anyway plays
      // the leave sound and clears the selected channel.
      // A direct call counts: it has no channel.
      if (livekit.state.inCall) livekit.disconnect();
    case CallShortcut.clip:
      // Out of a call, or with clipping off, it says why and keeps nothing.
      livekit.clipCall();
  }
}

/// The action's name, in Settings and to the desktop.
String callShortcutTitle(CallShortcut action) => switch (action) {
  CallShortcut.mute => 'Mute',
  CallShortcut.deafen => 'Deafen',
  CallShortcut.leave => 'Leave call',
  CallShortcut.clip => 'Clip the call',
};
