import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

import 'key_shortcut.dart';

/// What a call shortcut does: the same as the mute, deafen and leave buttons,
/// and taking a clip of the call (Windows and Linux only: CALLS.md, "Clipping
/// a call").
enum CallShortcut { mute, deafen, leave, clip }

/// The keys picked for each [CallShortcut], each unset until chosen. Per
/// device, in `AppState`.
class CallShortcuts extends Equatable {
  final KeyShortcut? mute;
  final KeyShortcut? deafen;
  final KeyShortcut? leave;
  final KeyShortcut? clip;

  const CallShortcuts({this.mute, this.deafen, this.leave, this.clip});

  KeyShortcut? operator [](CallShortcut action) => switch (action) {
    CallShortcut.mute => mute,
    CallShortcut.deafen => deafen,
    CallShortcut.leave => leave,
    CallShortcut.clip => clip,
  };

  /// [action] on [keys], or unset with null. Keys another action had are
  /// taken from it, so one press never does two things.
  CallShortcuts withKeys(CallShortcut action, KeyShortcut? keys) {
    KeyShortcut? pick(CallShortcut other) {
      if (other == action) return keys;
      final had = this[other];
      return had == keys ? null : had;
    }

    return CallShortcuts(
      mute: pick(CallShortcut.mute),
      deafen: pick(CallShortcut.deafen),
      leave: pick(CallShortcut.leave),
      clip: pick(CallShortcut.clip),
    );
  }

  /// These less any shortcut on [keyId], whatever its modifiers: push-to-talk
  /// takes its key alone, and a mute on the same key flipped with every hold.
  CallShortcuts withoutKey(int keyId) {
    KeyShortcut? keep(CallShortcut action) {
      final keys = this[action];
      return keys?.keyId == keyId ? null : keys;
    }

    return CallShortcuts(
      mute: keep(CallShortcut.mute),
      deafen: keep(CallShortcut.deafen),
      leave: keep(CallShortcut.leave),
      clip: keep(CallShortcut.clip),
    );
  }

  /// The action [key], pressed with what [keys] holds, is bound to.
  CallShortcut? actionFor(LogicalKeyboardKey key, HardwareKeyboard keys) =>
      actionForKey(key.keyId, KeyShortcut.heldBy(keys));

  /// The action the key [keyId], pressed with [held], is bound to: for
  /// presses that come from outside Flutter, like the Windows hook.
  CallShortcut? actionForKey(int keyId, HeldModifiers held) {
    for (final action in CallShortcut.values) {
      if (this[action]?.matchesHeld(keyId, held) ?? false) return action;
    }
    return null;
  }

  factory CallShortcuts.fromJson(Map<String, dynamic> json) {
    KeyShortcut? read(String name) => switch (json[name]) {
      final Map<String, dynamic> keys => KeyShortcut.fromJson(keys),
      _ => null,
    };
    return CallShortcuts(
      mute: read('mute'),
      deafen: read('deafen'),
      leave: read('leave'),
      clip: read('clip'),
    );
  }

  Map<String, dynamic> toJson() => {
    'mute': mute?.toJson(),
    'deafen': deafen?.toJson(),
    'leave': leave?.toJson(),
    'clip': clip?.toJson(),
  };

  @override
  List<Object?> get props => [mute, deafen, leave, clip];
}
