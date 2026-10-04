import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/siws_sign_in.dart';

/// A sign-in refused for the device's clock is retried at the server's time,
/// which only works if the refusal is recognised; and when it cannot be got
/// round, the person is told what to fix rather than "Invalid or expired
/// token".
void main() {
  group('isClockRefusal', () {
    test("recognises both of GoTrue's refusals", () {
      expect(
        isClockRefusal('Solana message was issued too far in the future'),
        isTrue,
      );
      expect(isClockRefusal('Solana message was issued too long ago'), isTrue);
    });

    test('leaves every other failure alone', () {
      expect(isClockRefusal(null), isFalse);
      expect(isClockRefusal('Signature does not match'), isFalse);
      expect(isClockRefusal("Can't reach this server."), isFalse);
    });
  });

  group('clockRefusalMessage', () {
    test('says how far and which way the clock is off', () {
      expect(
        clockRefusalMessage(const Duration(hours: -12)),
        startsWith("This device's clock is 12 hours fast"),
      );
      expect(
        clockRefusalMessage(const Duration(minutes: 25)),
        startsWith("This device's clock is 25 minutes slow"),
      );
      expect(
        clockRefusalMessage(const Duration(minutes: -61)),
        contains('61 minutes fast'),
      );
      expect(
        clockRefusalMessage(const Duration(minutes: 95)),
        contains('2 hours slow'),
      );
    });

    test('still points at the clock when the server gave no time', () {
      expect(clockRefusalMessage(null), contains("this device's clock"));
    });
  });
}
