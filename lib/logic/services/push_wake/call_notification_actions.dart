import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/repositories/secure_storage_repository.dart';
import '../../../data/repositories/server_repository.dart';
import '../../helper_methods.dart';
import '../notification_ids.dart';
import '../storage_namespace.dart';
import 'wake_calls.dart';
import 'wake_index.dart';
import 'wake_server_reader.dart';

/// Decline pressed on a call's notification, with the app not running.
///
/// Android runs this in a fresh background isolate, as it does a push: no
/// cubits, no session. So it does what the push isolate does — reads the
/// seed, signs in to the one server with a fresh SIWS login — and ends the
/// call there, which is what tells the caller. Answer never comes here: it
/// opens the app, which answers from where it has a room to join.
@pragma('vm:entry-point')
Future<void> callActionInBackground(NotificationResponse response) async {
  if (response.actionId != 'decline') return;
  final call = CallNotificationPayload.decode(response.payload);
  if (call == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await declineFromNotification(call);
}

/// Ends [call] on its server from an isolate that has nothing but the seed.
Future<void> declineFromNotification(CallNotificationPayload call) async {
  try {
    StorageNamespace.apply();
    final seedB64 = await SecureStorageRepository().getMasterSeed();
    if (seedB64 == null) return;
    final server = (await WakeIndex.read()).servers
        .where((s) => s.id == call.serverId)
        .firstOrNull;
    if (server == null) return;
    final token = await WakeServerReader().signIn(
      server,
      CryptoRepository.fromBase64(seedB64),
    );
    if (token == null) return;
    await ServerRepository().endDmCall(
      server.supabaseUrl,
      anonKey: server.anonKey,
      bearerToken: token,
      callId: call.callId,
    );
    // The stop push that follows finds nothing to take down.
    final shown = await WakeCalls.read();
    shown.forget(call.callId);
    await shown.save();
  } catch (e) {
    HelperMethods.printDebug('declineFromNotification: $e');
  }
}
