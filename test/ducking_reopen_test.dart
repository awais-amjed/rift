import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/ducking/ducking_cubit.dart';

void main() {
  test('a duck right after an unduck is the same one carrying on', () {
    // A 1.5.0 report: Windows restored other sounds and lowered them again
    // 1 ms later as the call's sound reopened, and the person saw two toasts.
    final restored = DateTime(2026, 10, 19, 18, 9, 22, 251);
    expect(
      DuckingCubit.reopened(
        restored,
        restored.add(const Duration(milliseconds: 1)),
      ),
      isTrue,
    );
    // A new call's duck, long after the last one ended, counts again.
    expect(
      DuckingCubit.reopened(restored, restored.add(const Duration(minutes: 5))),
      isFalse,
    );
    // The first duck of all has nothing to carry on from.
    expect(DuckingCubit.reopened(null, restored), isFalse);
  });
}
