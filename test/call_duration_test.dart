import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/services/call_duration.dart';

void main() {
  group('formatCallDuration', () {
    test('seconds in the first minute, then whole minutes', () {
      expect(formatCallDuration(const Duration(seconds: 7)), '7s');
      expect(formatCallDuration(const Duration(seconds: 61)), '1m');
      expect(
        formatCallDuration(const Duration(minutes: 12, seconds: 59)),
        '12m',
      );
    });

    test('hours past an hour, and an even hour stands alone', () {
      expect(
        formatCallDuration(const Duration(hours: 1, minutes: 4, seconds: 7)),
        '1h 4m',
      );
      expect(formatCallDuration(const Duration(hours: 2, seconds: 30)), '2h');
    });

    test('days past a day, with hours and never minutes', () {
      expect(
        formatCallDuration(const Duration(days: 1, hours: 2, minutes: 59)),
        '1d 2h',
      );
      expect(formatCallDuration(const Duration(days: 3, minutes: 5)), '3d');
    });

    test('a clock that ran backwards reads as a call just started', () {
      expect(formatCallDuration(const Duration(seconds: -3)), '0s');
    });
  });

  group('LiveKitState.connectedAt', () {
    final at = DateTime(2026, 9, 16, 12);

    test('is kept while the call stays connected', () {
      final state = const LiveKitState().copyWith(
        connectionState: LiveKitConnectionState.connected,
        connectedAt: at,
      );
      expect(state.copyWith(isMicEnabled: false).connectedAt, at);
    });

    test('goes the moment the call is anything but connected', () {
      final state = const LiveKitState().copyWith(
        connectionState: LiveKitConnectionState.connected,
        connectedAt: at,
      );
      for (final next in [
        LiveKitConnectionState.disconnected,
        LiveKitConnectionState.connecting,
        LiveKitConnectionState.error,
      ]) {
        expect(state.copyWith(connectionState: next).connectedAt, isNull);
      }
    });
  });
}
