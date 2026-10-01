// The client's join bookkeeping is `@internal`, and it is exactly what is
// under test here.
// ignore_for_file: invalid_use_of_internal_member

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

// The patches to supabase's realtime client in third_party/realtime_client
// (RIFT_PATCHES.md). Each of the first four fails on the 2.13.0 release, so
// these also catch the dependency override being dropped while upstream still
// lacks the fixes. Measured live: a gateway outage left a client with its
// `server:`, `user:` and open `chat:` topics stuck joining and off the socket,
// no live messages until a restart.

/// A client that believes its socket is open. There is no connection, so
/// nothing is sent anywhere; what is under test is the bookkeeping.
RealtimeClient _open() =>
    RealtimeClient('ws://127.0.0.1:9/realtime/v1')
      ..connState = SocketStates.open;

/// Joins pushed so far, from the client's own `push` log lines.
int _joins(List<String> log) =>
    log.where((l) => l.startsWith('push ') && l.contains(' join (')).length;

void main() {
  test('removing one unsent channel leaves the others', () {
    final client = _open();
    final a = client.channel('a');
    final b = client.channel('b');
    client.remove(a);
    expect(client.channels, [same(b)]);
  });

  test('a join sent again while its timer runs gets a fresh ref', () {
    final client = _open();
    final channel = client.channel('x')..subscribe();
    final first = channel.joinRef;
    channel.joinPush.resend(const Duration(seconds: 10));
    expect(channel.joinRef, isNotEmpty, reason: 'no reply could match it');
    expect(channel.joinRef, isNot(first));
  });

  test('a rejoin never leaves the channel asking', () {
    final client = _open();
    final channel = client.channel('x')..subscribe();
    channel.rejoin();
    expect(
      client.channels,
      contains(same(channel)),
      reason: 'off the socket, its join reply reaches nobody',
    );
    expect(channel.isJoining, isTrue);
  });

  test('a second channel on a topic still replaces the first', () {
    final client = _open();
    final old = client.channel('x')..subscribe();
    final replacement = client.channel('x')..subscribe();
    expect(old.isLeaving || old.isClosed, isTrue);
    expect(client.channels, contains(same(replacement)));
  });

  // What the outage did: every failed reconnect armed each channel's rejoin
  // timer, one of them fired while the join sent on reconnecting was still
  // waiting for its reply, and the channel left itself.
  test('a dropped socket arms no rejoin timer, and a slow join after the '
      'reconnect is left alone until its own timeout', () {
    fakeAsync((async) {
      final log = <String>[];
      final client = _open()..logger = (kind, msg, _) => log.add('$kind $msg');
      final channel = client.channel('x')..subscribe();
      final firstRef = channel.joinRef;

      // realtime_client marks the socket closed, then errors every channel.
      client.connState = SocketStates.closed;
      channel.trigger('phx_error', 'socket closed');
      final beforeOutage = _joins(log);
      async.elapse(const Duration(seconds: 60));
      expect(_joins(log), beforeOutage, reason: 'nothing retries a dead socket');

      // The socket opens, and rejoins the errored channel, as _onConnOpen does.
      client.connState = SocketStates.open;
      channel.rejoin();
      expect(channel.joinRef, isNot(anyOf('', firstRef)));
      final afterReconnect = _joins(log);

      async.elapse(const Duration(seconds: 9));
      expect(_joins(log), afterReconnect, reason: 'its reply is still due');
      expect(client.channels, contains(same(channel)));
      expect(channel.isJoining, isTrue);

      // Its own timeout is what asks again.
      async.elapse(const Duration(seconds: 3));
      expect(_joins(log), greaterThan(afterReconnect));
      expect(client.channels, contains(same(channel)));
    });
  });
}
