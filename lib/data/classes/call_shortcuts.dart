import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

import 'key_shortcut.dart';

/// What a call shortcut does: the same as the mute and deafen buttons.
enum CallShortcut { mute, deafen }

/// The keys picked for mute and deafen, each unset until chosen. Per device,
/// in `AppState`.
class CallShortcuts extends Equatable {
  final KeyShortcut? mute;
  final KeyShortcut? deafen;

  const CallShortcuts({this.mute, this.deafen});

  KeyShortcut? operator [](CallShortcut action) => switch (action) {
    CallShortcut.mute => mute,
    CallShortcut.deafen => deafen,
  };

  /// [action] on [keys], or unset with null. Keys the other action had are
  /// taken from it, so one press never does both.
  CallShortcuts withKeys(CallShortcut action, KeyShortcut? keys) {
    KeyShortcut? keep(KeyShortcut? other) => other == keys ? null : other;
    return switch (action) {
      CallShortcut.mute => CallShortcuts(mute: keys, deafen: keep(deafen)),
      CallShortcut.deafen => CallShortcuts(mute: keep(mute), deafen: keys),
    };
  }

  /// The action [key], pressed with what [keys] holds, is bound to.
  CallShortcut? actionFor(LogicalKeyboardKey key, HardwareKeyboard keys) {
    for (final action in CallShortcut.values) {
      if (this[action]?.matches(key, keys) ?? false) return action;
    }
    return null;
  }

  factory CallShortcuts.fromJson(Map<String, dynamic> json) {
    KeyShortcut? read(String name) => switch (json[name]) {
      final Map<String, dynamic> keys => KeyShortcut.fromJson(keys),
      _ => null,
    };
    return CallShortcuts(mute: read('mute'), deafen: read('deafen'));
  }

  Map<String, dynamic> toJson() => {
    'mute': mute?.toJson(),
    'deafen': deafen?.toJson(),
  };

  @override
  List<Object?> get props => [mute, deafen];
}
