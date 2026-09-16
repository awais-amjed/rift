import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/services/call_duration.dart';

void main() {
  group('formatCallDuration', () {
    test('minutes and seconds under an hour, both padded', () {
      expect(formatCallDuration(const Duration(seconds: 7)), '00:07');
      expect(
        formatCallDuration(const Duration(minutes: 12, seconds: 4)),
        '12:04',
      );
    });

    test('hours are added past an hour, and are not padded', () {
      expect(
        formatCallDuration(const Duration(hours: 1, minutes: 4, seconds: 7)),
        '1:04:07',
      );
    });

    test('a clock that ran backwards reads as a call just started', () {
      expect(formatCallDuration(const Duration(seconds: -3)), '00:00');
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
