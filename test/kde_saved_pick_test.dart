import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/shared_window.dart';
import 'package:rift/logic/services/kde_saved_pick.dart';

Uint8List bytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// What Plasma 6.6 saved for a pick of Konsole's window (Oct 14 2026), read
/// back from the PermissionStore: the map's outputs (none), region (none),
/// then the window list. Its length is at [countAt], the title's at
/// [titleAt].
final konsole = bytes(
  '000000030000000e006f0075007400700075007400730000000900000000000000000c00'
  '72006500670069006f006e00000013000000000000000000ffffffffffffffff0000000e'
  '00770069006e0064006f00770073000100000000000019514c6973743c57696e646f7752'
  '6573746f7265496e666f3e00000000010000001e006f00720067002e006b00640065002e'
  '006b006f006e0073006f006c006500000024007e0020003a002000620061007300680020'
  '20140020004b006f006e0073006f006c0065',
);
const countAt = 120;
const titleAt = 158;

/// The same for Firefox, picked from Rift.
final firefox = bytes(
  '000000030000000e006f0075007400700075007400730000000900000000000000000c00'
  '72006500670069006f006e00000013000000000000000000ffffffffffffffff0000000e'
  '00770069006e0064006f00770073000100000000000019514c6973743c57696e646f7752'
  '6573746f7265496e666f3e000000000100000026006f00720067002e006d006f007a0069'
  '006c006c0061002e00660069007200650066006f00780000004000520069006600740020'
  '0074006f006e006500200074006500730074002020140020004d006f007a0069006c006c'
  '0061002000460069007200650066006f0078',
);

void main() {
  test('reads the app and title KDE saved for a window', () {
    expect(
      KdeSavedPick.window(konsole),
      const SharedWindow(appId: 'org.kde.konsole', title: '~ : bash — Konsole'),
    );
    expect(
      KdeSavedPick.window(firefox),
      const SharedWindow(
        appId: 'org.mozilla.firefox',
        title: 'Rift tone test — Mozilla Firefox',
      ),
    );
  });

  test('a pick of a screen has no window', () {
    // The same map with an empty window list.
    final screen = Uint8List.fromList(konsole.sublist(0, countAt + 4))
      ..setRange(countAt, countAt + 4, [0, 0, 0, 0]);
    expect(KdeSavedPick.window(screen), isNull);
  });

  test('bytes cut short are no window, not a crash', () {
    for (final end in [10, countAt + 2, countAt + 10, titleAt + 10]) {
      expect(KdeSavedPick.window(konsole.sublist(0, end)), isNull);
    }
  });

  test('a null title reads as empty', () {
    final noTitle = Uint8List.fromList([
      ...konsole.sublist(0, titleAt),
      0xff, 0xff, 0xff, 0xff, //
    ]);
    expect(
      KdeSavedPick.window(noTitle),
      const SharedWindow(appId: 'org.kde.konsole', title: ''),
    );
  });
}
