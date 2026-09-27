import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/dm_call.dart';
import 'package:rift/data/enums/dm_call_outcome.dart';
import 'package:rift/logic/services/call_log_label.dart';
import 'package:rift/logic/services/call_refusal.dart';
import 'package:rift/logic/services/dm_call_ledger.dart';
import 'package:rift/logic/services/notification_ids.dart';
import 'package:rift/logic/services/push_wake/wake_calls.dart';

/// Calls between two members: the row as the app reads it, the bookkeeping
/// that decides what rings, and the words a call leaves in its conversation.
void main() {
  const me = 'aaaaaaaa-0000-4000-8000-000000000001';
  const ben = 'bbbbbbbb-0000-4000-8000-000000000002';
  final t0 = DateTime.utc(2026, 9, 27, 12);

  Map<String, dynamic> row({
    String id = 'c1',
    String caller = ben,
    String callee = me,
    DateTime? started,
    DateTime? answered,
    DateTime? ended,
    String? outcome,
  }) => {
    'id': id,
    'caller_id': caller,
    'callee_id': callee,
    'started_at': (started ?? t0).toIso8601String(),
    'answered_at': answered?.toIso8601String(),
    'ended_at': ended?.toIso8601String(),
    'outcome': outcome,
    'peer_id': caller == me ? callee : caller,
    'peer_name': 'Ben',
    'peer_chat_public_key': 'chat-ben',
  };

  DmCall call({
    String id = 'c1',
    String caller = ben,
    String callee = me,
    DateTime? started,
    DateTime? answered,
    DateTime? ended,
    String? outcome,
  }) => DmCall.fromJson(
    row(
      id: id,
      caller: caller,
      callee: callee,
      started: started,
      answered: answered,
      ended: ended,
      outcome: outcome,
    ),
  );

  group('DmCall', () {
    test('reads the row my_dm_calls answers with', () {
      final c = call(answered: t0.add(const Duration(seconds: 5)));
      expect(c.peerId, ben);
      expect(c.peerChatPublicKey, 'chat-ben');
      expect(c.isLive, isTrue);
      expect(c.isRinging, isFalse);
      expect(c.isIncomingFor(me), isTrue);
      expect(c.roomName, 'dm-c1');
    });

    test('is ringing until answered, and over once ended', () {
      expect(call().isRinging, isTrue);
      final over = call(
        answered: t0,
        ended: t0.add(const Duration(minutes: 12, seconds: 30)),
        outcome: 'completed',
      );
      expect(over.isEnded, isTrue);
      expect(over.outcome, DmCallOutcome.completed);
      expect(over.duration, const Duration(minutes: 12, seconds: 30));
    });

    test('a list keeps the rows that parse and drops the rest', () {
      final calls = DmCall.listFrom([
        row(),
        {'id': 'broken'},
        'not a row',
      ]);
      expect(calls.map((c) => c.id), ['c1']);
      expect(DmCall.listFrom(null), isEmpty);
    });

    test('an outcome this build does not know reads as none', () {
      expect(DmCallOutcome.fromString('rerouted'), isNull);
    });
  });

  group('DmCallLedger.apply', () {
    test('a call ringing me rings here; my own ringing out does not', () {
      final folded = DmCallLedger.apply(
        serverId: 's1',
        myId: me,
        ringing: const [],
        activeId: null,
        fetched: [
          call(id: 'in'),
          call(id: 'out', caller: me, callee: ben),
        ],
        now: t0.add(const Duration(seconds: 3)),
      );
      expect(folded.ringing.map((e) => e.call.id), ['in']);
    });

    test('a ring past its window is not offered', () {
      final folded = DmCallLedger.apply(
        serverId: 's1',
        myId: me,
        ringing: const [],
        activeId: null,
        fetched: [call()],
        now: t0.add(DmCallLedger.ringWindow),
      );
      expect(folded.ringing, isEmpty);
    });

    test('another server\'s rings pass through untouched', () {
      final elsewhere = (serverId: 's2', call: call(id: 'x'));
      final folded = DmCallLedger.apply(
        serverId: 's1',
        myId: me,
        ringing: [elsewhere],
        activeId: null,
        fetched: const [],
        now: t0,
      );
      expect(folded.ringing, [elsewhere]);
    });

    test('the call I am in is followed, and never rings', () {
      final folded = DmCallLedger.apply(
        serverId: 's1',
        myId: me,
        ringing: const [],
        activeId: 'c1',
        fetched: [call(answered: t0)],
        now: t0,
      );
      expect(folded.ringing, isEmpty);
      expect(folded.active?.isLive, isTrue);
    });

    test('a ring that ended missed is reported once, for a missed call', () {
      final ringing = [(serverId: 's1', call: call())];
      final folded = DmCallLedger.apply(
        serverId: 's1',
        myId: me,
        ringing: ringing,
        activeId: null,
        fetched: [
          call(ended: t0.add(const Duration(seconds: 45)), outcome: 'missed'),
        ],
        now: t0.add(const Duration(seconds: 46)),
      );
      expect(folded.ringing, isEmpty);
      expect(folded.missed.map((c) => c.id), ['c1']);
    });

    test('a ring answered on my other device is not missed', () {
      final folded = DmCallLedger.apply(
        serverId: 's1',
        myId: me,
        ringing: [(serverId: 's1', call: call())],
        activeId: null,
        fetched: [call(answered: t0.add(const Duration(seconds: 4)))],
        now: t0.add(const Duration(seconds: 5)),
      );
      expect(folded.ringing, isEmpty);
      expect(folded.missed, isEmpty);
    });

    test('expire drops rings whose doorbell never came', () {
      final kept = DmCallLedger.expire([
        (serverId: 's1', call: call(id: 'old')),
        (
          serverId: 's1',
          call: call(id: 'new', started: t0.add(const Duration(seconds: 40))),
        ),
      ], t0.add(const Duration(seconds: 50)));
      expect(kept.map((e) => e.call.id), ['new']);
    });
  });

  group('CallLogLabel', () {
    test('an answered call gives its length, to the minute', () {
      final label = CallLogLabel.of(
        call(
          answered: t0,
          ended: t0.add(const Duration(minutes: 12, seconds: 40)),
          outcome: 'completed',
        ),
        myId: me,
      )!;
      expect(label.text, 'Call · 12 min');
      expect(label.kind, CallLogKind.answered);
    });

    test('a missed call reads differently to each end', () {
      final missed = call(ended: t0, outcome: 'missed');
      expect(CallLogLabel.of(missed, myId: me)!.text, 'Missed call from Ben');
      final mine = call(caller: me, callee: ben, ended: t0, outcome: 'missed');
      expect(CallLogLabel.of(mine, myId: me)!.text, 'Ben didn\'t answer');
    });

    test('a call given up on at once is nothing to the person rung', () {
      final cancelled = call(ended: t0, outcome: 'cancelled');
      expect(CallLogLabel.of(cancelled, myId: me), isNull);
      final mine = call(
        caller: me,
        callee: ben,
        ended: t0,
        outcome: 'cancelled',
      );
      expect(CallLogLabel.of(mine, myId: me)?.text, 'You cancelled a call');
    });

    test('lengths read the way a person says them', () {
      expect(
        CallLogLabel.duration(const Duration(seconds: 40)),
        'under a minute',
      );
      expect(CallLogLabel.duration(const Duration(minutes: 60)), '1 h');
      expect(CallLogLabel.duration(const Duration(minutes: 65)), '1 h 5 min');
    });
  });

  group('CallRefusal', () {
    test('names every refusal the call functions raise', () {
      for (final code in [
        'call_needs_conversation',
        'call_not_accepted',
        'call_rate_limited',
        'timed_out',
        'cannot_connect',
        'user_not_found',
        'call_not_ringing',
        'call_ended',
        'call_not_found',
      ]) {
        expect(
          CallRefusal.describe(code, peerName: 'Ben'),
          isNotNull,
          reason: '$code has no sentence',
        );
      }
      expect(CallRefusal.describe('P0001', peerName: 'Ben'), isNull);
    });

    test('a block never says it is a block', () {
      final sentence = CallRefusal.describe(
        'call_not_accepted',
        peerName: 'Ben',
      )!;
      expect(sentence.toLowerCase(), isNot(contains('block')));
    });
  });

  group('WakeCalls — a phone woken by a push', () {
    test('a ring is posted once, however many pushes follow', () {
      final shown = WakeCalls({});
      final first = shown.apply(
        serverId: 's1',
        myId: me,
        fetched: [call()],
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(first.single, isA<WakeCallRinging>());
      final again = shown.apply(
        serverId: 's1',
        myId: me,
        fetched: [call()],
        now: t0.add(const Duration(seconds: 4)),
      );
      expect(again, isEmpty);
      expect(shown.shownOn('s1'), ['c1']);
    });

    test('my own call ringing out is not put up', () {
      final changes = WakeCalls({}).apply(
        serverId: 's1',
        myId: me,
        fetched: [call(caller: me, callee: ben)],
        now: t0,
      );
      expect(changes, isEmpty);
    });

    test('a missed ring becomes a missed call; an answered one goes', () {
      final missed = WakeCalls({'c1': (serverId: 's1', peerName: 'Ben')});
      final change = missed
          .apply(
            serverId: 's1',
            myId: me,
            fetched: [call(ended: t0, outcome: 'missed')],
            now: t0,
          )
          .single;
      expect(change, isA<WakeCallStopped>());
      expect((change as WakeCallStopped).missed, isTrue);
      expect(missed.shownOn('s1'), isEmpty);

      final answered = WakeCalls({'c1': (serverId: 's1', peerName: 'Ben')});
      final gone =
          answered
                  .apply(
                    serverId: 's1',
                    myId: me,
                    fetched: [call(answered: t0)],
                    now: t0,
                  )
                  .single
              as WakeCallStopped;
      expect(gone.missed, isFalse);
    });

    test('another server\'s rings are left alone', () {
      final shown = WakeCalls({'x': (serverId: 's2', peerName: 'Sam')});
      shown.apply(serverId: 's1', myId: me, fetched: const [], now: t0);
      expect(shown.shownOn('s2'), ['x']);
    });
  });

  group('the call notification', () {
    test('carries which call on which server, and reads back', () {
      const payload = CallNotificationPayload('s1', 'c1');
      final back = CallNotificationPayload.decode(payload.encode())!;
      expect(back.serverId, 's1');
      expect(back.callId, 'c1');
      expect(CallNotificationPayload.decode('something else'), isNull);
      expect(CallNotificationPayload.decode(null), isNull);
    });

    test('has one id per call, the same on every run', () {
      expect(callNotificationId('c1'), callNotificationId('c1'));
      expect(callNotificationId('c1'), isNot(callNotificationId('c2')));
      expect(callNotificationId('c1'), isNot(stableNotificationId('c1')));
    });
  });
}
