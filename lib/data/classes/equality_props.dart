import 'package:flutter/foundation.dart' show setEquals;

/// A set in an `Equatable`'s props, compared by membership in linear time.
///
/// Equatable compares two sets by searching one for each member of the other,
/// which is quadratic: nothing for a handful of ids, but a server's online
/// members compared on every presence change is not a handful.
class SetProp {
  final Set<Object?> value;

  const SetProp(this.value);

  @override
  bool operator ==(Object other) =>
      other is SetProp && setEquals(other.value, value);

  @override
  int get hashCode => Object.hashAllUnordered(value);
}

/// Bytes in an `Equatable`'s props, compared by identity.
///
/// Bytes are never edited in place — new content is a new list — so the same
/// object is the same content, and comparing a picked file byte by byte on
/// every emit would cost as much as the file is big.
class IdentityProp {
  final Object? value;

  const IdentityProp(this.value);

  @override
  bool operator ==(Object other) =>
      other is IdentityProp && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}
