import 'dart:convert';
import 'dart:io';

import '../../../data/classes/dm_call.dart';
import '../../../data/enums/dm_call_outcome.dart';
import '../dm_call_ledger.dart';
import '../storage_namespace.dart';

/// What a push-woken isolate should do about one DM call.
sealed class WakeCallChange {
  final String serverId;
  final String callId;
  final String peerName;

  const WakeCallChange(this.serverId, this.callId, this.peerName);
}

/// A call is ringing this person: put up its notification, with Answer and
/// Decline on it.
class WakeCallRinging extends WakeCallChange {
  const WakeCallRinging(super.serverId, super.callId, super.peerName);
}

/// A call this device was showing has stopped ringing. [missed] turns its
/// notification into "Missed call"; otherwise — answered on another device,
/// declined, given up on at once — it is simply taken down.
class WakeCallStopped extends WakeCallChange {
  final bool missed;

  const WakeCallStopped(
    super.serverId,
    super.callId,
    super.peerName, {
    required this.missed,
  });
}

/// The calls a phone is showing as ringing, kept between wakes.
///
/// A doorbell is empty, so the second push for a call — the one that says it
/// stopped ringing — arrives into an isolate that has forgotten the first.
/// This file is how it knows there is a notification to take down, and whose.
class WakeCalls {
  final Map<String, ({String serverId, String peerName})> _shown;

  WakeCalls(Map<String, ({String serverId, String peerName})> shown)
    : _shown = shown;

  static const _fileName = 'push_wake_calls.json';

  /// Call ids shown on [serverId] — the ones to ask the server about.
  List<String> shownOn(String serverId) => [
    for (final entry in _shown.entries)
      if (entry.value.serverId == serverId) entry.key,
  ];

  /// Stop remembering [callId] — its notification was answered from.
  void forget(String callId) => _shown.remove(callId);

  /// What [fetched] — one server's `my_dm_calls` answer — means for the
  /// notifications, given what this device already shows.
  ///
  /// Pure apart from the bookkeeping it updates, which is the point of it: a
  /// ring is posted once, and one that has stopped is taken down or turned
  /// into a missed call once.
  List<WakeCallChange> apply({
    required String serverId,
    required String myId,
    required List<DmCall> fetched,
    required DateTime now,
  }) {
    final changes = <WakeCallChange>[];
    final byId = {for (final call in fetched) call.id: call};

    for (final id in shownOn(serverId)) {
      final call = byId[id];
      if (call != null && call.isRinging) continue;
      final peer = _shown.remove(id)!.peerName;
      changes.add(
        WakeCallStopped(
          serverId,
          id,
          call?.peerName ?? peer,
          missed: call?.outcome == DmCallOutcome.missed,
        ),
      );
    }

    for (final call in fetched) {
      if (!call.isRinging || !call.isIncomingFor(myId)) continue;
      if (now.difference(call.startedAt) >= DmCallLedger.ringWindow) continue;
      if (_shown.containsKey(call.id)) continue;
      _shown[call.id] = (serverId: serverId, peerName: call.peerName);
      changes.add(WakeCallRinging(serverId, call.id, call.peerName));
    }
    return changes;
  }

  static Future<File> _file() async {
    final dir = await StorageNamespace.profileDirectory(
      StorageNamespace.apply(),
    );
    await Directory(dir).create(recursive: true);
    return File('$dir/$_fileName');
  }

  static Future<WakeCalls> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return WakeCalls({});
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return WakeCalls({});
      return WakeCalls({
        for (final entry in json.entries)
          if (entry.value case {
            'server_id': final String serverId,
            'peer_name': final String peerName,
          })
            '${entry.key}': (serverId: serverId, peerName: peerName),
      });
    } catch (_) {
      return WakeCalls({});
    }
  }

  Future<void> save() async {
    try {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          for (final entry in _shown.entries)
            entry.key: {
              'server_id': entry.value.serverId,
              'peer_name': entry.value.peerName,
            },
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {
      // Best-effort: the cost is a call notification left up until it times
      // out on its own.
    }
  }
}
