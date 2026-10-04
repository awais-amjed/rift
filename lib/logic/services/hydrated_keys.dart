import 'dart:convert';
import 'dart:typed_data';

/// The names the persisted cubits save their state under.
///
/// hydrated_bloc names each one after `runtimeType.toString()` unless told
/// otherwise. The Windows installer is built obfuscated — inno_bundle passes
/// `--obfuscate` and has no switch to leave it out — and a release web build
/// is minified, so there the name was a scrambled one (`Sjb`, `Ujb`) that
/// changed from one build to the next. Each update then looked under a name
/// nothing had been saved under, and the server list, push-to-talk and every
/// other setting started over. Linux, macOS and Android builds were never
/// obfuscated, so these are the names they have always used.
abstract final class HydratedKeys {
  static const app = 'AppCubit';
  static const server = 'ServerCubit';
  static const theme = 'ThemeCubit';
  static const token = 'TokenCubit';

  static const all = [app, server, theme, token];
}

/// Finds the state a build from before [HydratedKeys] saved under a
/// scrambled name, so the update that brings the fixed names does not lose
/// it too.
///
/// A scrambled name says nothing, but each state has a shape of its own — the
/// server list is the only one with `servers` and `orderClock` — so a record
/// is recognised by its keys. Every build left its own records behind, so
/// there can be several of each; the one written last is the one the build
/// the person last ran was using.
abstract final class HydratedKeyRecovery {
  /// Which fixed name [record] would have been saved under, or null for one
  /// that is none of them.
  static String? kindOf(Object? record) {
    if (record is! Map) return null;
    bool has(String key) => record.containsKey(key);
    if (has('servers') && has('orderClock')) return HydratedKeys.server;
    if (has('pushToTalkEnabled') && has('noiseSuppression')) {
      return HydratedKeys.app;
    }
    if (has('themeMode') && has('paletteId')) return HydratedKeys.theme;
    if (has('tokens') && record.length == 1) return HydratedKeys.token;
    return null;
  }

  /// For each fixed name with nothing under it in [records], the key of the
  /// record to copy there.
  ///
  /// [writeOrder] lists keys from least to most recently written. A key
  /// missing from it counts as older than any it lists; with no order at all
  /// (the web, where storage keeps none) the first candidate is taken.
  static Map<String, String> plan(
    Map<String, Object?> records,
    List<String> writeOrder,
  ) {
    final rank = {for (final (i, key) in writeOrder.indexed) key: i};
    final chosen = <String, String>{};
    for (final MapEntry(:key, :value) in records.entries) {
      if (HydratedKeys.all.contains(key)) continue;
      final kind = kindOf(value);
      if (kind == null || records.containsKey(kind)) continue;
      final current = chosen[kind];
      if (current == null || (rank[key] ?? -1) > (rank[current] ?? -1)) {
        chosen[kind] = key;
      }
    }
    return chosen;
  }

  /// The string keys of a Hive box file, from least to most recently
  /// written.
  ///
  /// Each frame is its length (4 bytes, little-endian, counting itself and
  /// the checksum at its end), then the key: type 1 is a string, one length
  /// byte and its UTF-8 bytes; type 0 an integer. Hive appends every write and
  /// keeps file order when it compacts, so a key's last frame is its last
  /// write. A torn tail ends the walk; what came before it still counts.
  static List<String> keysInWriteOrder(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final order = <String>{}; // insertion-ordered
    var offset = 0;
    while (offset + 6 <= bytes.length) {
      final length = data.getUint32(offset, Endian.little);
      if (length < 8 || offset + length > bytes.length) break;
      if (bytes[offset + 4] == 1) {
        final keyLength = bytes[offset + 5];
        final start = offset + 6;
        if (start + keyLength > offset + length) break;
        final key = utf8.decode(
          bytes.sublist(start, start + keyLength),
          allowMalformed: true,
        );
        order
          ..remove(key)
          ..add(key);
      }
      offset += length;
    }
    return order.toList();
  }
}
