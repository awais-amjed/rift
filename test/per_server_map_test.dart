import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/per_server_map.dart';

/// The shape every per-server tally uses, and the invariant three of them lean
/// on: **a zero count is an absent key, and an empty inner map is an absent
/// server.** Whichever one stops pruning is the one that leaves a server in the
/// map forever after its last message is read.
void main() {
  group('replaced', () {
    test('swaps one server and leaves the others alone', () {
      final next = PerServerMap.replaced(
        {
          's1': {'a': 1},
          's2': {'b': 2},
        },
        's1',
        {'c': 3},
      );
      expect(next, {
        's1': {'c': 3},
        's2': {'b': 2},
      });
    });

    test('an empty replacement removes the server', () {
      final next = PerServerMap.replaced(
        {
          's1': {'a': 1},
        },
        's1',
        const {},
      );
      expect(next.containsKey('s1'), isFalse);
    });

    test('does not mutate what it was given', () {
      final original = {
        's1': {'a': 1},
      };
      PerServerMap.replaced(original, 's1', {'b': 2});
      expect(original, {
        's1': {'a': 1},
      });
    });
  });

  group('incremented', () {
    test('creates the server and the key', () {
      expect(PerServerMap.incremented(const {}, 's1', 'a'), {
        's1': {'a': 1},
      });
    });

    test('adds to what is there', () {
      final next = PerServerMap.incremented(
        {
          's1': {'a': 4},
        },
        's1',
        'a',
      );
      expect(next['s1']!['a'], 5);
    });
  });

  group('withEntry', () {
    test('sets one key without disturbing its neighbours', () {
      final next = PerServerMap.withEntry(
        {
          's1': {'a': 1},
        },
        's1',
        'b',
        2,
      );
      expect(next['s1'], {'a': 1, 'b': 2});
    });
  });

  group('without', () {
    test('removes one key', () {
      final next = PerServerMap.without(
        {
          's1': {'a': 1, 'b': 2},
        },
        's1',
        'a',
      );
      expect(next!['s1'], {'b': 2});
    });

    test('prunes the server when its last key goes', () {
      final next = PerServerMap.without(
        {
          's1': {'a': 1},
          's2': {'b': 2},
        },
        's1',
        'a',
      );
      expect(next!.keys, ['s2']);
    });

    test('answers null when there was nothing to remove', () {
      // Which is what lets a caller hand back the same state instance rather
      // than emitting one identical to the last.
      expect(PerServerMap.without(const {}, 's1', 'a'), isNull);
      expect(
        PerServerMap.without(
          {
            's1': {'a': 1},
          },
          's1',
          'zzz',
        ),
        isNull,
      );
      expect(
        PerServerMap.without(
          {
            's1': {'a': 1},
          },
          'other',
          'a',
        ),
        isNull,
      );
    });
  });
}
