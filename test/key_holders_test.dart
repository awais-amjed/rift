import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/key_holders.dart';

void main() {
  test('online holders come first, each group by name', () {
    final holders = orderKeyHolders(
      names: {'k': 'Kofi', 'n': 'nadia', 'a': 'Awais', 'd': 'Dee'},
      onlineIds: {'n', 'd'},
      me: null,
    );
    expect(holders.map((h) => h.name), ['Dee', 'nadia', 'Awais', 'Kofi']);
    expect(holders.map((h) => h.online), [true, true, false, false]);
  });

  test('the member waiting is never listed as a holder', () {
    final holders = orderKeyHolders(
      names: {'me': 'Me', 'k': 'Kofi'},
      onlineIds: {'me', 'k'},
      me: 'me',
    );
    expect(holders.map((h) => h.id), ['k']);
  });

  test('nobody to ask is an empty list, not an error', () {
    expect(
      orderKeyHolders(names: const {}, onlineIds: const {}, me: 'me'),
      isEmpty,
    );
  });
}
