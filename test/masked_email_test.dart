import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/masked_email.dart';

void main() {
  test('keeps the first letter and the domain, hides the rest', () {
    expect(MaskedEmail.of('hey.hasan@gmail.com'), 'h••••••••@gmail.com');
    expect(MaskedEmail.of('ab@x.io'), 'a•••@x.io');
  });

  test('the dots do not give the length away past a point', () {
    expect(
      MaskedEmail.of('averyveryverylongname@example.org'),
      'a••••••••@example.org',
    );
  });

  test('something that is not an address is all dots', () {
    expect(MaskedEmail.of('nope'), '••••');
    expect(MaskedEmail.of(''), '•••');
  });
}
