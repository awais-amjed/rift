import 'dart:io';
import 'dart:typed_data';

/// The file-system half of saving something the user picked a place for.
///
/// Kept out of the widget that asks, so the dialog flow can stay UI-only and
/// the one `dart:io` dependency lives here.
class DiskFile {
  const DiskFile._();

  static Future<bool> exists(String path) => File(path).exists();

  static Future<void> write(String path, Uint8List bytes) =>
      File(path).writeAsBytes(bytes);

  /// The last segment of [path], for saying which file in a prompt.
  static String name(String path) => File(path).uri.pathSegments.last;
}
