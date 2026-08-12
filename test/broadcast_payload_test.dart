import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/broadcast_payload.dart';

void main() {
  group('BroadcastPayload', () {
    test('reads the flattened form the server actually delivers', () {
      // What a broadcast callback receives today: the sent keys sit alongside
      // `event` and `type` rather than under a `payload` key.
      const message = {
        'event': 'message_changed',
        'type': 'broadcast',
        'message_id': '42',
      };
      expect(BroadcastPayload.stringOf(message, 'message_id'), '42');
    });

    test('reads the nested form too', () {
      const message = {
        'event': 'message_changed',
        'type': 'broadcast',
        'payload': {'message_id': '42'},
      };
      expect(BroadcastPayload.stringOf(message, 'message_id'), '42');
    });

    test('a missing key is null, not a crash', () {
      expect(BroadcastPayload.stringOf(const {'type': 'broadcast'}, 'x'), null);
    });

    test('a non-string value is null — callers expect ids as strings', () {
      expect(
        BroadcastPayload.stringOf(const {'message_id': 42}, 'message_id'),
        null,
      );
    });

    test('a payload key that is not a map falls back to the message', () {
      const message = {'payload': 'nonsense', 'from': 'u1'};
      expect(BroadcastPayload.stringOf(message, 'from'), 'u1');
    });
  });
}
