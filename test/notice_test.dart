import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/notice.dart';
import 'package:rift/logic/cubits/screenshare/screenshare_cubit.dart';

/// A cubit tells the person something by setting a notice in its state;
/// `NoticeListeners` shows each new one once.
void main() {
  test('the same words twice are two notices', () {
    // States compare by value: without its own id, a second identical
    // failure would make an equal state that emit drops, and say nothing.
    final first = Notice.error('Could not vote');
    final second = Notice.error('Could not vote');
    expect(first, isNot(second));
    expect(first, first);
  });

  test('a state carrying a new notice is a new state', () {
    const quiet = ScreenshareState();
    final told = quiet.copyWith(notice: Notice.error('No frames arrived'));
    final toldAgain = told.copyWith(notice: Notice.error('No frames arrived'));
    expect(told, isNot(quiet));
    expect(toldAgain, isNot(told));
    // Anything else copied keeps the notice, so it is not shown again.
    expect(told.copyWith(), told);
  });
}
