import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm/nm.dart';
import 'package:rift/logic/cubits/network/network_cubit.dart';
import 'package:rift/logic/services/linux_connectivity.dart';

void main() {
  const settle = Duration(milliseconds: 40);
  const longer = Duration(milliseconds: 80);
  const none = [ConnectivityResult.none];
  const wifi = [ConnectivityResult.wifi];

  late StreamController<List<ConnectivityResult>> changes;

  NetworkCubit cubit({List<ConnectivityResult> initial = wifi}) => NetworkCubit(
    changes: changes.stream,
    check: () async => initial,
    settle: settle,
  );

  setUp(() => changes = StreamController.broadcast());
  tearDown(() => changes.close());

  test('only `none`, or nothing at all, is offline', () {
    expect(NetworkCubit.isOffline(none), isTrue);
    expect(NetworkCubit.isOffline(const []), isTrue);
    expect(NetworkCubit.isOffline(wifi), isFalse);
    // A VPN reported beside nothing else is still a connection.
    expect(NetworkCubit.isOffline(const [ConnectivityResult.vpn]), isFalse);
    expect(
      NetworkCubit.isOffline(const [
        ConnectivityResult.none,
        ConnectivityResult.ethernet,
      ]),
      isFalse,
    );
  });

  test(
    'starting with no network reports it once the settle has passed',
    () async {
      final c = cubit(initial: none);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.offline, isFalse, reason: 'not before the settle');
      await Future<void>.delayed(longer);
      expect(c.state.offline, isTrue);
      await c.close();
    },
  );

  test('a drop shorter than the settle never shows', () async {
    final c = cubit();
    changes.add(none);
    await Future<void>.delayed(settle ~/ 4);
    changes.add(wifi);
    await Future<void>.delayed(longer);
    expect(c.state.offline, isFalse);
    await c.close();
  });

  test('coming back is reported at once', () async {
    final c = cubit();
    changes.add(none);
    await Future<void>.delayed(longer);
    expect(c.state.offline, isTrue);
    changes.add(wifi);
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

  test('on Linux, a network with no way out is offline', () {
    // Wi-Fi off with Tailscale or loopback still up reads `limited`, not
    // `none`; counting only `none` is how the chip never showed.
    expect(
      LinuxConnectivity.isOffline(NetworkManagerConnectivityState.limited),
      isTrue,
    );
    expect(
      LinuxConnectivity.isOffline(NetworkManagerConnectivityState.none),
      isTrue,
    );
    for (final state in [
      NetworkManagerConnectivityState.full,
      NetworkManagerConnectivityState.portal,
      NetworkManagerConnectivityState.unknown,
    ]) {
      expect(LinuxConnectivity.isOffline(state), isFalse, reason: '$state');
    }
  });
}
