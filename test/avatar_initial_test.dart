import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/squircle_avatar.dart';

/// The DM header draws the peer's handle with its `@`, and the conversation
/// list beside it draws the bare handle — so the same person had `@` on the
/// avatar in one place and `L` in the other. The initial is the first letter
/// or digit, never the punctuation in front of it.
void main() {
  group('SquircleAvatar.initialOf', () {
    test('skips the @ a handle is shown with', () {
      expect(SquircleAvatar.initialOf('@lana_clean'), 'L');
      expect(SquircleAvatar.initialOf('lana_clean'), 'L');
    });

    test('an ordinary name is its first letter', () {
      expect(SquircleAvatar.initialOf('Benny'), 'B');
      expect(SquircleAvatar.initialOf('rift test'), 'R');
    });

    test('a leading digit counts — a name may start with one', () {
      expect(SquircleAvatar.initialOf('2cool'), '2');
    });

    test('skips any run of punctuation, not just one character', () {
      expect(SquircleAvatar.initialOf('!!! cool'), 'C');
      expect(SquircleAvatar.initialOf('___x'), 'X');
    });

    test('a name with nothing alphanumeric keeps its first character', () {
      // That *is* what somebody would call it, so inventing a "?" would be
      // worse than showing it.
      expect(SquircleAvatar.initialOf('日本語'), '日本語'[0]);
    });

    test('an empty name has nothing to show', () {
      expect(SquircleAvatar.initialOf(''), '?');
    });
  });
}
