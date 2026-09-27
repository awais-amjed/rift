import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_limits.dart';
import 'package:rift/presentation/screens/home/screenshare/sections/bitrate_section.dart';

/// The bitrate picker against a server that caps shares.
///
/// Pure: these are the two static rules the widget draws itself from, and the
/// bug they exist to stop is silent — a picker lighting one number while the
/// share sends another.
void main() {
  group('the bitrate picker under a server cap', () {
    test('no cap leaves the ladder exactly as it was', () {
      expect(
        BitrateSection.optionsFor(ServerLimits.unlimited),
        BitrateSection.bitrateOptions,
      );
      expect(BitrateSection.effectiveFor(10, ServerLimits.unlimited), 10);
    });

    test('a cap between two rungs becomes a rung of its own', () {
      // The share is clamped to the cap, not snapped to the option below it,
      // so 3 has to be selectable — otherwise the picker lights 2 and the
      // stream sends 3.
      expect(BitrateSection.optionsFor(3), [2, 3, 4, 6, 8, 10, 12, 14, 15]);
      expect(BitrateSection.effectiveFor(15, 3), 3);
      expect(BitrateSection.optionsFor(3), contains(3));
    });

    test('a cap that is already a rung adds nothing', () {
      expect(BitrateSection.optionsFor(8), BitrateSection.bitrateOptions);
      expect(BitrateSection.effectiveFor(15, 8), 8);
    });

    test('a cap above the ladder changes nothing but the sentence', () {
      expect(BitrateSection.optionsFor(50), BitrateSection.bitrateOptions);
      expect(BitrateSection.effectiveFor(15, 50), 15);
    });

    test('a modest setting is left alone under a generous cap', () {
      expect(BitrateSection.effectiveFor(4, 12), 4);
    });

    test('whatever is lit is always a chip that exists', () {
      // The invariant the whole thing rests on: every cap an operator could
      // type leaves the effective value somewhere in the row.
      for (var cap = 1; cap <= 20; cap++) {
        for (final stored in BitrateSection.bitrateOptions) {
          expect(
            BitrateSection.optionsFor(cap),
            contains(BitrateSection.effectiveFor(stored, cap)),
            reason: 'cap $cap with $stored stored lights a chip that is absent',
          );
        }
      }
    });
  });
}
