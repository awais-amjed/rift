import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/services/dm_call_split.dart';

/// Where the line between a DM call and its messages falls, in windows the
/// share was not chosen in.
void main() {
  test('the default share of a tall pane', () {
    expect(DmCallSplit.heightFor(1000, K.dmCallStageShare), 460);
  });

  test('never shorter than the call can be drawn in', () {
    expect(DmCallSplit.heightFor(1000, 0.05), K.dmCallStageMin);
  });

  test('always leaves the messages a few lines and the composer', () {
    expect(DmCallSplit.heightFor(1000, 0.99), 1000 - K.dmCallChatMin);
  });

  test('a pane too short for both keeps the call whole', () {
    expect(DmCallSplit.heightFor(300, 0.9), K.dmCallStageMin);
  });

  test('a drag is stored as the share it lands on, clamped the same way', () {
    expect(DmCallSplit.shareFor(1000, 600), closeTo(0.6, 1e-9));
    expect(
      DmCallSplit.shareFor(1000, 990),
      closeTo((1000 - K.dmCallChatMin) / 1000, 1e-9),
    );
  });

  test('nonsense in, the default out', () {
    expect(DmCallSplit.heightFor(double.infinity, 0.5), K.dmCallStageMin);
    expect(DmCallSplit.shareFor(0, 100), K.dmCallStageShare);
    expect(DmCallSplit.heightFor(1000, double.nan), 1000 * K.dmCallStageShare);
  });
}
