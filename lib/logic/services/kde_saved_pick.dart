import 'dart:convert';
import 'dart:typed_data';

import '../../data/classes/shared_window.dart';

/// Reads the window out of what KDE saves for a remembered ScreenCast pick:
/// `('KDE', 1, <bytes>)` in the PermissionStore, the bytes being a Qt
/// `QDataStream` of a `QVariantMap` (xdg-desktop-portal-kde, `RestoreData`).
///
/// Its `windows` entry holds a type Qt knows only by name,
/// `QList<WindowRestoreInfo>`: a count, then an app id and a title per window.
/// The reader finds that name rather than walking the map, so entries KDE
/// adds before it later (outputs, region, size) cannot throw it off. Seen
/// Oct 14 2026 with Plasma 6.6.
class KdeSavedPick {
  const KdeSavedPick._();

  /// Qt writes a named type as its name with the terminating NUL, after a
  /// big-endian length that counts the NUL.
  static final _marker = Uint8List.fromList([
    0, 0, 0, 25, // length, NUL included
    ...ascii.encode('QList<WindowRestoreInfo>'),
    0,
  ]);

  /// A null `QString`, written as its length.
  static const _nullString = 0xFFFFFFFF;

  /// The first window in [payload], or null when there is none or the
  /// bytes are not in the shape above.
  static SharedWindow? window(Uint8List payload) {
    final at = _find(payload, _marker);
    if (at < 0) return null;
    // The list's length follows the name. (The byte saying whether the value
    // is null comes before the name, not after it.)
    var offset = at + _marker.length;
    final data = ByteData.sublistView(payload);
    if (offset + 4 > payload.length || data.getUint32(offset) == 0) {
      return null;
    }
    offset += 4;
    final appId = _string(data, offset);
    if (appId == null) return null;
    final title = _string(data, appId.end);
    if (title == null) return null;
    return SharedWindow(appId: appId.text, title: title.text);
  }

  /// A `QString` at [offset]: its length in bytes, then UTF-16 big-endian.
  static ({String text, int end})? _string(ByteData data, int offset) {
    if (offset + 4 > data.lengthInBytes) return null;
    final length = data.getUint32(offset);
    offset += 4;
    if (length == _nullString) return (text: '', end: offset);
    if (length.isOdd || offset + length > data.lengthInBytes) return null;
    final units = [
      for (var i = 0; i < length; i += 2) data.getUint16(offset + i),
    ];
    return (text: String.fromCharCodes(units), end: offset + length);
  }

  static int _find(Uint8List bytes, Uint8List pattern) {
    outer:
    for (var i = 0; i + pattern.length <= bytes.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
