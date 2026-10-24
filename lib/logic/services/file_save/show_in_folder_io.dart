import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../open_link.dart';

/// Opens the folder holding [path] in the system's file manager, with the
/// file picked out where the desktop can do that. False when nothing opened.
///
/// Only ever a file the person saved themselves, at a place they chose.
Future<bool> showInFolder(String path) async {
  try {
    if (Platform.isWindows) {
      // explorer answers 1 even when it opened, so its exit code says nothing.
      await Process.start('explorer.exe', ['/select,', path]);
      return true;
    }
    if (Platform.isMacOS) {
      return (await Process.run('open', ['-R', path])).exitCode == 0;
    }
    if (Platform.isLinux && await _showItem(path)) return true;
  } catch (_) {}
  return openOwnFolder(File(path).parent.path);
}

/// The freedesktop file manager call that selects a file in its folder —
/// Nautilus, Dolphin, Nemo and Thunar answer it. A desktop without one
/// falls back to opening the folder.
Future<bool> _showItem(String path) async {
  final client = DBusClient.session();
  try {
    await client.callMethod(
      destination: 'org.freedesktop.FileManager1',
      path: DBusObjectPath('/org/freedesktop/FileManager1'),
      interface: 'org.freedesktop.FileManager1',
      name: 'ShowItems',
      values: [
        DBusArray.string([Uri.file(path).toString()]),
        const DBusString(''),
      ],
      replySignature: DBusSignature(''),
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    await client.close();
  }
}

/// Opens [path], a file the person just saved, in whatever the system opens
/// that kind of file with. False when nothing would.
///
/// Only from the person's own press on "Open": the file came from somebody
/// else, and opening it runs the program its name points at — an `.exe` on
/// Windows runs itself.
Future<bool> openSavedFile(String path) async {
  try {
    return await launchUrl(Uri.file(path));
  } catch (_) {
    return false;
  }
}
