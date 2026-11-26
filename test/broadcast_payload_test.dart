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

    // The database sends ids as JSON numbers; a client sends them as strings.
    test('a numeric id reads as its digits', () {
      expect(
        BroadcastPayload.stringOf(const {'message_id': 42}, 'message_id'),
        '42',
      );
    });

    test('any other non-string value is null', () {
      expect(BroadcastPayload.stringOf(const {'x': true}, 'x'), null);
      expect(BroadcastPayload.stringOf(const {'x': <String>[]}, 'x'), null);
    });

    test('a payload key that is not a map falls back to the message', () {
      const message = {'payload': 'nonsense', 'from': 'u1'};
      expect(BroadcastPayload.stringOf(message, 'from'), 'u1');
    });

    // A `members` ring names who moved (062); without `ids` it means
    // anybody may have.
    test('reads the ids a ring names, flattened or nested', () {
      expect(
        BroadcastPayload.idsOf(const {
          'type': 'broadcast',
          'ids': ['a', 'b'],
        }),
        {'a', 'b'},
      );
      expect(
        BroadcastPayload.idsOf(const {
          'type': 'broadcast',
          'payload': {
            'ids': ['a'],
          },
        }),
        {'a'},
      );
    });

    test('a ring naming nobody is null, not an empty set', () {
      expect(BroadcastPayload.idsOf(const {'type': 'broadcast'}), isNull);
      expect(
        BroadcastPayload.idsOf(const {'type': 'broadcast', 'ids': 'a'}),
        isNull,
      );
    });
  });
}
