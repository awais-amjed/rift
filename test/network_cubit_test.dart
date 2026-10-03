import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm/nm.dart';
import 'package:rift/data/enums/network_reading.dart';
import 'package:rift/logic/cubits/network/network_cubit.dart';
import 'package:rift/logic/services/linux_connectivity.dart';

void main() {
  const settle = Duration(milliseconds: 40);
  const longer = Duration(milliseconds: 80);
  const online = NetworkReading.online;
  const offline = NetworkReading.offline;
  const unsure = NetworkReading.unsure;

  late StreamController<NetworkReading> changes;

  NetworkCubit cubit({
    NetworkReading initial = online,
    Future<bool?> Function()? confirm,
    Duration recheck = NetworkCubit.recheck,
  }) => NetworkCubit(
    changes: changes.stream,
    check: () async => initial,
    confirm: confirm,
    settle: settle,
    recheck: recheck,
  );

  setUp(() => changes = StreamController.broadcast());
  tearDown(() => changes.close());

  test('only `none`, or nothing at all, is offline', () {
    const none = [ConnectivityResult.none];
    expect(NetworkCubit.reading(none), offline);
    expect(NetworkCubit.reading(const []), offline);
    expect(NetworkCubit.reading(const [ConnectivityResult.wifi]), online);
    // A VPN reported beside nothing else is still a connection.
    expect(NetworkCubit.reading(const [ConnectivityResult.vpn]), online);
    expect(
      NetworkCubit.reading(const [
        ConnectivityResult.none,
        ConnectivityResult.ethernet,
      ]),
      online,
    );
  });

  test(
    'starting with no network reports it once the settle has passed',
    () async {
      final c = cubit(initial: offline);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.offline, isFalse, reason: 'not before the settle');
      await Future<void>.delayed(longer);
      expect(c.state.offline, isTrue);
      await c.close();
    },
  );

  test('a drop shorter than the settle never shows', () async {
    final c = cubit();
    changes.add(offline);
    await Future<void>.delayed(settle ~/ 4);
    changes.add(online);
    await Future<void>.delayed(longer);
    expect(c.state.offline, isFalse);
    await c.close();
  });

  test('coming back is reported at once', () async {
    final c = cubit();
    changes.add(offline);
    await Future<void>.delayed(longer);
    expect(c.state.offline, isTrue);
    changes.add(online);
    await Future<void>.delayed(Duration.zero);
    expect(c.state.offline, isFalse);
    await c.close();
  });

  test('a platform that cannot answer leaves it online', () async {
    final c = NetworkCubit(
      changes: changes.stream,
      check: () => Future.error(Exception('no plugin')),
      settle: settle,
    );
    await Future<void>.delayed(longer);
    expect(c.state.offline, isFalse);
    await c.close();
  });

  group('when the platform is unsure', () {
    test('a server answering keeps it online', () async {
      // NetworkManager's check address blocked by a Pi-hole, on a machine
      // whose internet works: "No internet" there was a false alarm.
      final c = cubit(initial: unsure, confirm: () async => true);
      await Future<void>.delayed(longer);
      expect(c.state.offline, isFalse);
      await c.close();
    });

    test('no server answering is offline', () async {
      // Wi-Fi off with Tailscale still up reads `limited`, not `none`.
      final c = cubit(initial: unsure, confirm: () async => false);
      await Future<void>.delayed(longer);
      expect(c.state.offline, isTrue);
      await c.close();
    });

    test('with nobody to ask, the platform\'s doubt stands', () async {
      final c = cubit(initial: unsure, confirm: () async => null);
      await Future<void>.delayed(longer);
      expect(c.state.offline, isTrue);
      await c.close();
    });

    test('it asks again, and a server coming back clears it', () async {
      var answers = false;
      final c = cubit(
        initial: unsure,
        confirm: () async => answers,
        recheck: settle,
      );
      await Future<void>.delayed(longer);
      expect(c.state.offline, isTrue);
      answers = true;
      await Future<void>.delayed(longer);
      expect(c.state.offline, isFalse);
      await c.close();
    });

    test('an answer the platform has overtaken is dropped', () async {
      final reply = Completer<bool?>();
      final c = cubit(initial: unsure, confirm: () => reply.future);
      await Future<void>.delayed(Duration.zero);
      changes.add(offline);
      reply.complete(true);
      await Future<void>.delayed(longer);
      expect(c.state.offline, isTrue);
      await c.close();
    });
  });

  test('on Linux, `limited` is a doubt, not a verdict', () {
    expect(
      LinuxConnectivity.read(NetworkManagerConnectivityState.limited),
      unsure,
    );
    expect(
      LinuxConnectivity.read(NetworkManagerConnectivityState.none),
      offline,
    );
    for (final state in [
      NetworkManagerConnectivityState.full,
      NetworkManagerConnectivityState.portal,
      NetworkManagerConnectivityState.unknown,
    ]) {
      expect(LinuxConnectivity.read(state), online, reason: '$state');
    }
  });
}
