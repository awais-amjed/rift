import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/repositories/secure_storage_repository.dart';
import '../../helper_methods.dart';
import '../notification_service.dart';
import '../storage_namespace.dart';
import 'wake_calls.dart';
import 'wake_central_reader.dart';
import 'wake_index.dart';
import 'wake_item.dart';
import 'wake_marks.dart';
import 'wake_server_reader.dart';

/// What happens when a push wakes the app.
///
/// The push itself says nothing — deliberately: an FCM payload is readable by
/// Google and forwardable by whatever relays it, so anything put in one is
/// disclosed to both. It is a doorbell. This is the part that answers it: read
/// the seed, ask every server what is unread, decrypt the newest message in
/// each conversation, and say something true about it.
///
/// Everything it needs is already on the device, which is the whole reason the
/// doorbell can be empty. Nothing about the message travels through anyone
/// else's hands to reach the notification.
///
/// It runs in a background isolate with none of the app's state, so it holds
/// nothing across wakes except two small files: the [WakeIndex] the app leaves
/// behind saying which servers this device is on, and the [WakeMarks] saying
/// what has already been announced.
class PushWakeService {
  const PushWakeService._();

  /// How many notifications one wake may post. Beyond this it is a wall rather
  /// than news, and the app itself is a tap away for the rest.
  static const maxNotifications = 5;

  /// What to say when there is a doorbell but no way to answer it — no seed,
  /// nothing readable, a network that is down. It is worth saying: something
  /// did arrive, and the alternative is silence about a real message.
  static const fallbackTitle = 'Rift';
  static const fallbackBody = 'You have a new message';

  static Future<void> run({
    WakeServerReader? servers,
    WakeCentralReader? central,
    SecureStorageRepository? storage,
  }) async {
    final answered = await _harvest(
      servers: servers,
      central: central,
      storage: storage,
    );
    if (!answered) await _fallback();
  }

  /// Reads every source and posts what it found, returning whether the wake
  /// was answered — false means the generic notice is owed.
  ///
  /// Split from [run] so the fallback is posted *outside* this try. Returning
  /// `_fallback()` from inside it handed back a future nobody awaited, so a
  /// notification that failed to post threw past the catch written to handle
  /// it, into a background isolate where nothing is listening.
  static Future<bool> _harvest({
    WakeServerReader? servers,
    WakeCentralReader? central,
    SecureStorageRepository? storage,
  }) async {
    try {
      final suffix = StorageNamespace.apply();
      final seedB64 = await (storage ?? SecureStorageRepository())
          .getMasterSeed();
      if (seedB64 == null) return false;
      final seed = CryptoRepository.fromBase64(seedB64);

      final marks = await WakeMarks.read();
      final index = await WakeIndex.read();
      final calls = await WakeCalls.read();
      final callChanges = <WakeCallChange>[];

      final harvests = <WakeHarvest>[
        await (central ?? WakeCentralReader()).read(
          seed,
          marks,
          storageSuffix: suffix,
        ),
        for (final server in index.servers)
          await (servers ?? WakeServerReader()).read(
            server,
            seed,
            marks,
            calls: calls,
            callChanges: callChanges,
          ),
      ];

      // Calls before messages: a person waiting on the line is the one thing
      // here that stops being answerable in a few seconds.
      final names = {for (final s in index.servers) s.id: s.name};
      for (final change in callChanges) {
        await _post(change, names[change.serverId] ?? 'Rift');
      }
      await calls.save();

      final items = [for (final harvest in harvests) ...harvest.items];
      if (items.isEmpty) {
        // Nothing new is a real answer — a doorbell for a message already
        // announced, or one read on another device. Only say something when
        // the silence would be a guess: a source that could not be reached, or
        // no source to reach at all.
        final failed = harvests.any((h) => h.failed);
        if (failed || index.servers.isEmpty) return false;
        return true;
      }

      for (final item in items.take(maxNotifications)) {
        await NotificationService.instance.showMessage(
          title: item.notice.title,
          body: item.notice.body,
          id: item.notificationId,
        );
        marks.mark(item.scope, item.messageId);
      }
      await marks.save();
      return true;
    } catch (e) {
      HelperMethods.printDebug('PushWakeService: wake failed – $e');
      return false;
    }
  }

  static Future<void> _post(WakeCallChange change, String serverName) =>
      switch (change) {
        WakeCallRinging() => NotificationService.instance.showIncomingCall(
          serverId: change.serverId,
          callId: change.callId,
          peerName: change.peerName,
          serverName: serverName,
        ),
        WakeCallStopped(missed: true) =>
          NotificationService.instance.showMissedCall(
            callId: change.callId,
            peerName: change.peerName,
            serverName: serverName,
          ),
        WakeCallStopped() => NotificationService.instance.cancelCall(
          change.callId,
        ),
      };

  static Future<void> _fallback() => NotificationService.instance.showMessage(
    title: fallbackTitle,
    body: fallbackBody,
  );
}
