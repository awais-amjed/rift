import 'dart:ui';

import '../enums/server_permission.dart';

/// A named set of permission bits on one server (migration 018).
class Role {
  final String id;
  final String name;

  /// Hex, or null for a role that exists to carry permissions rather than to
  /// be seen. A null colour means the member's name is drawn as usual.
  final String? color;

  /// Higher is more senior. Not a display preference: every delegation rule
  /// is decided on this and nothing else, so a role's position is as much a
  /// permission as anything in [permissions].
  final int position;

  final int permissions;

  /// The implicit baseline everybody has. Never assigned to anyone, never
  /// deleted, always position 0 — so it is the one role that cannot be handed
  /// out or taken away, only edited.
  final bool isEveryone;

  /// The role every member is given when they register (migration 025).
  ///
  /// Unlike [isEveryone] it is a real assignment — it can be taken away, and it
  /// shows in the roles editor and the per-member menu like any other. What it
  /// is *not* is worth a chip beside somebody's name: everybody has it, so it
  /// distinguishes nobody and only crowds out the roles that do.
  final bool isDefault;

  /// The one role that is held by exactly one person (migration 013).
  ///
  /// Nobody hands it out and nobody edits it: it goes to the first person who
  /// registers, and moves only through `transfer_ownership`. It outranks every
  /// other role by position alone, which is why the ladder needs no special
  /// case for it — only the screens that would offer to assign it do.
  final bool isOwner;

  const Role({
    required this.id,
    required this.name,
    required this.position,
    required this.permissions,
    this.color,
    this.isEveryone = false,
    this.isDefault = false,
    this.isOwner = false,
  });

  bool carries(ServerPermission permission) => permissions.carries(permission);

  /// The colour to draw this role in, or null to leave the text alone.
  Color? get displayColor {
    final hex = color;
    if (hex == null || hex.length != 7) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  factory Role.fromJson(Map<String, dynamic> json) => Role(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String?,
    position: (json['position'] as num?)?.toInt() ?? 0,
    permissions: (json['permissions'] as num?)?.toInt() ?? 0,
    isEveryone: json['is_everyone'] == true,
    isDefault: json['is_default'] == true,
    isOwner: json['is_owner'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'position': position,
    'permissions': permissions,
    'is_everyone': isEveryone,
    'is_default': isDefault,
    'is_owner': isOwner,
  };

  Role copyWith({
    String? name,
    String? color,
    bool clearColor = false,
    int? position,
    int? permissions,
  }) => Role(
    id: id,
    name: name ?? this.name,
    color: clearColor ? null : (color ?? this.color),
    position: position ?? this.position,
    permissions: permissions ?? this.permissions,
    isEveryone: isEveryone,
    isDefault: isDefault,
    isOwner: isOwner,
  );
}
