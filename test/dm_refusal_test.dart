import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/dm_link_state.dart';
import 'package:rift/data/enums/dm_policy.dart';
import 'package:rift/logic/services/dm_refusal.dart';
import 'package:rift/logic/services/edit_refusal.dart';
import 'package:rift/logic/services/pin_ops.dart';

/// What a sender is told when the server turns a DM down.
void main() {
  group('DmRefusal', () {
    test('names every refusal the DM gate raises', () {
      for (final code in [
        'dm_request_pending',
        'dm_not_accepted',
        'dm_rate_limited',
        'timed_out',
      ]) {
        expect(
          DmRefusal.describe(code, peerName: 'Sam'),
          isNotNull,
          reason: '$code has no sentence',
        );
      }
    });

    test('a block never says it is a block', () {
      // The server raises dm_not_accepted for both a block and a "no one new"
      // setting, on purpose; the sentence must not undo that.
      final sentence = DmRefusal.describe('dm_not_accepted', peerName: 'Sam')!;
      expect(sentence.toLowerCase(), isNot(contains('block')));
    });

    test('anything else is left to the caller', () {
      expect(DmRefusal.describe('P0001', peerName: 'Sam'), isNull);
      expect(DmRefusal.describe(null, peerName: 'Sam'), isNull);
    });
  });

  group('EditRefusal', () {
    test('a refused channel edit is a time-out, the only cause there is', () {
      expect(
        EditRefusal.describe('42501', timedOut: false),
        contains('timed out'),
      );
    });

    test('a refused DM edit reads as a refused DM unless timed out', () {
      expect(
        EditRefusal.describe('42501', timedOut: false, peerName: 'Sam'),
        DmRefusal.describe('dm_not_accepted', peerName: 'Sam'),
      );
      expect(
        EditRefusal.describe('42501', timedOut: true, peerName: 'Sam'),
        contains('timed out'),
      );
    });

    test('anything else is left to the caller', () {
      expect(EditRefusal.describe('P0001', timedOut: true), isNull);
      expect(EditRefusal.describe(null, timedOut: true), isNull);
    });
  });

  group('refused pins', () {
    test('a time-out and a block each have words, and a block is not named', () {
      expect(PinOps.errorFor('timed_out'), contains('timed out'));
      final blocked = PinOps.errorFor('dm_not_accepted');
      expect(blocked, isNotNull);
      expect(blocked!.toLowerCase(), isNot(contains('block')));
    });
  });

  group('reading the server\'s words', () {
    test('an unknown link state reads as open, so no composer locks', () {
      expect(DmLinkState.fromString('something-new'), DmLinkState.open);
      expect(DmLinkState.fromString(null), DmLinkState.open);
      expect(DmLinkState.fromString('waiting'), DmLinkState.waiting);
    });

    test('only asked and ignored are requests to me', () {
      expect(
        [
          for (final s in DmLinkState.values)
            if (s.isRequestToMe) s,
        ],
        [DmLinkState.asked, DmLinkState.ignored],
      );
    });

    test('an unknown DM setting reads as the server default', () {
      expect(DmPolicy.fromString(null), DmPolicy.everyone);
      expect(DmPolicy.fromString('nobody'), DmPolicy.nobody);
      for (final p in DmPolicy.values) {
        expect(DmPolicy.fromString(p.toJson()), p);
      }
    });
  });
}
