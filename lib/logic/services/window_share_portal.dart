import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import '../../data/classes/shared_window.dart';
import '../helper_methods.dart';
import 'kde_saved_pick.dart';
import 'linux_desktop_entry.dart';
import 'portal_request.dart';

/// What came of asking the desktop for a window to share.
sealed class WindowPick {
  const WindowPick();
}

/// The user closed the picker: no share.
class WindowPickCancelled extends WindowPick {
  const WindowPickCancelled();
}

/// The picker could not be run. The share goes ahead and libwebrtc asks
/// itself, as it did before Rift asked first.
class WindowPickFailed extends WindowPick {
  const WindowPickFailed();
}

/// A window, and the token that shares it without asking again
/// (`ScreenShareConfig.portalChoice`). [window] is null when the desktop
/// saved nothing Rift can read about it.
class WindowPicked extends WindowPick {
  final String token;
  final SharedWindow? window;

  const WindowPicked(this.token, this.window);
}

/// Linux under Wayland: the desktop's own window picker, run by Rift before
/// a share starts, so Rift knows which app's window it is and can pick the
/// sound to go with it.
///
/// The ScreenCast portal tells an app nothing about what was picked — only a
/// PipeWire stream. But a pick asked to be remembered (`persist_mode` 2) is
/// saved in the PermissionStore under its restore token, and GNOME and KDE
/// save the window's app id and title there. Rift reads that, and hands the
/// token to libwebrtc, which restores the same window with no second picker
/// (verified Oct 14 2026 on GNOME 50 and KDE Plasma 6.6). GNOME
/// deletes the saved pick once the token is used and KDE keeps it, so
/// [forget] is called after every share.
///
/// Other desktops save nothing Rift can read (`HostPlatform`).
class WindowSharePortal {
  const WindowSharePortal._();

  static const _interface = 'org.freedesktop.portal.ScreenCast';
  static const _table = 'screencast';
  static const _storeName = 'org.freedesktop.impl.portal.PermissionStore';
  static final _store = DBusObjectPath(
    '/org/freedesktop/impl/portal/PermissionStore',
  );
  static const _tag = 'WindowSharePortal';

  /// The picker waits on a person.
  static const _timeout = Duration(minutes: 10);

  /// `types`: a window, not a monitor.
  static const _window = 2;

  /// `persist_mode`: until revoked, which is what saves the pick where it
  /// can be read.
  static const _untilRevoked = 2;

  /// The user saying no.
  static const _cancelled = 1;

  static Future<WindowPick> pick() async {
    final client = DBusClient.session();
    final requests = PortalRequests(
      client,
      interface: _interface,
      tag: _tag,
      timeout: _timeout,
    );
    DBusObjectPath? session;
    try {
      // As the app's own connection is, or the pick is saved for nobody.
      await requests.register(LinuxDesktopEntry.appId);
      final created = await requests.call(
        'CreateSession',
        (token) => [
          DBusDict.stringVariant({
            'handle_token': DBusString(token),
            'session_handle_token': DBusString(
              requests.nextToken('rift_share'),
            ),
          }),
        ],
      );
      final handle = created.results?['session_handle']?.asString();
      if (handle == null) return const WindowPickFailed();
      session = DBusObjectPath(handle);

      final selected = await requests.call(
        'SelectSources',
        (token) => [
          session!,
          DBusDict.stringVariant({
            'handle_token': DBusString(token),
            'types': const DBusUint32(_window),
            'multiple': const DBusBoolean(false),
            'persist_mode': const DBusUint32(_untilRevoked),
          }),
        ],
      );
      if (selected.results == null) return const WindowPickFailed();

      final started = await requests.call(
        'Start',
        (token) => [
          session!,
          const DBusString(''),
          DBusDict.stringVariant({'handle_token': DBusString(token)}),
        ],
      );
      if (started.code == _cancelled) return const WindowPickCancelled();
      final token = started.results?['restore_token']?.asString();
      if (token == null || token.isEmpty) return const WindowPickFailed();
      return WindowPicked(token, await _saved(client, token));
    } catch (e) {
      HelperMethods.printDebug('$_tag: unavailable – $e');
      return const WindowPickFailed();
    } finally {
      // The pick outlives its session: the token restores it.
      if (session != null) await requests.closeSession(session);
      await client.close();
    }
  }

  /// Deletes a pick that was never shared. Quiet when it is already gone.
  static Future<void> forget(String token) async {
    final client = DBusClient.session();
    try {
      await client.callMethod(
        destination: _storeName,
        path: _store,
        interface: _storeName,
        name: 'Delete',
        values: [const DBusString(_table), DBusString(token)],
        replySignature: DBusSignature(''),
      );
    } catch (_) {
      // Used, and so deleted by the portal.
    } finally {
      await client.close();
    }
  }

  /// What the desktop saved about the pick. GNOME's:
  /// `('GNOME', 1, <(t, t, [(id, type, <(app id, title)>)])>)`.
  /// KDE's: `('KDE', 1, <bytes>)` ([KdeSavedPick]).
  static Future<SharedWindow?> _saved(DBusClient client, String token) async {
    try {
      final reply = await client.callMethod(
        destination: _storeName,
        path: _store,
        interface: _storeName,
        name: 'Lookup',
        values: [const DBusString(_table), DBusString(token)],
        replySignature: DBusSignature('a{sas}v'),
      );
      final data = reply.values[1].asVariant().asStruct();
      if (data[1].asUint32() != 1) return null;
      return switch (data[0].asString()) {
        'GNOME' => _gnome(data[2].asVariant()),
        'KDE' => KdeSavedPick.window(
          Uint8List.fromList(data[2].asVariant().asByteArray().toList()),
        ),
        _ => null,
      };
    } catch (e) {
      HelperMethods.printDebug('$_tag: no saved pick to read – $e');
    }
    return null;
  }

  static SharedWindow? _gnome(DBusValue saved) {
    final streams = saved.asStruct()[2].asArray();
    for (final stream in streams) {
      final fields = stream.asStruct();
      if (fields[1].asUint32() != _window) continue;
      final window = fields[2].asVariant().asStruct();
      return SharedWindow(
        appId: window[0].asString(),
        title: unescape(window[1].asString()),
      );
    }
    return null;
  }

  /// GNOME saves the title as markup (`DON&apos;T`).
  static String unescape(String markup) => markup
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
