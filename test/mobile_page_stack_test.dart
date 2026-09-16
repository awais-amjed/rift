import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/mobile_page.dart';
import 'package:rift/logic/services/mobile_page_stack.dart';

void main() {
  const empty = MobilePageStack();

  test('opening a page puts it on top', () {
    expect(empty.opened(MobilePage.channelChat).top, MobilePage.channelChat);
  });

  test('a conversation replaces the conversation already open', () {
    final stack = empty
        .opened(MobilePage.channelChat)
        .opened(MobilePage.serverDm);
    expect(stack.pages, [MobilePage.serverDm]);
  });

  test('a conversation opened from a call sits above it', () {
    final stack = empty.opened(MobilePage.call).opened(MobilePage.channelChat);
    expect(stack.pages, [MobilePage.call, MobilePage.channelChat]);
  });

  test(
    'returning to the call from a conversation lifts the call to the top',
    () {
      final stack = empty
          .opened(MobilePage.call)
          .opened(MobilePage.channelChat)
          .opened(MobilePage.call);
      expect(stack.pages, [MobilePage.channelChat, MobilePage.call]);
    },
  );

  test('opening the page already on top changes nothing', () {
    final stack = empty.opened(MobilePage.friends);
    expect(stack.opened(MobilePage.friends), stack);
  });

  test(
    'closing takes only that page, and closing an absent one is a no-op',
    () {
      final stack = empty.opened(MobilePage.call).opened(MobilePage.centralDm);
      expect(stack.closed(MobilePage.call).pages, [MobilePage.centralDm]);
      expect(stack.closed(MobilePage.friends), same(stack));
    },
  );

  test('droppedBy names what a change removed', () {
    final before = empty.opened(MobilePage.call).opened(MobilePage.serverDm);
    final after = before.opened(MobilePage.centralDm);
    expect(before.droppedBy(after), [MobilePage.serverDm]);
  });
}
