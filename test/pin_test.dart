import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/services/message_permissions.dart';
import 'package:rift/logic/services/pin_ops.dart';

void main() {
  final at = DateTime.utc(2026, 9, 26, 10);
  ChatMessage message(
    String id, {
    DateTime? pinnedAt,
    bool locked = false,
    bool pending = false,
    bool ephemeral = false,
  }) => ChatMessage(
    id: id,
    authorId: 'a',
    authorName: 'A',
    text: 'hi',
    sentAt: at,
    isMine: false,
    pinnedAt: pinnedAt,
    isLocked: locked,
    isPending: pending,
    isEphemeral: ephemeral,
  );

  test('a row says when it was pinned, and a missing pin is none', () {
    expect(PinOps.pinnedAtOf({'pinned_at': at.toIso8601String()}), at);
    expect(PinOps.pinnedAtOf({'pinned_at': null}), isNull);
    expect(PinOps.pinnedAtOf({}), isNull);
  });

  test('pinning one message leaves the others and their order alone', () {
    final list = [message('1'), message('2'), message('3')];
    final pinned = PinOps.withPin(list, id: '2', pinnedAt: at);
    expect(pinned.map((m) => m.id), ['1', '2', '3']);
    expect(pinned.map((m) => m.isPinned), [false, true, false]);
    final unpinned = PinOps.withPin(pinned, id: '2', pinnedAt: null);
    expect(unpinned.every((m) => !m.isPinned), isTrue);
  });

  test('copyWith keeps a pin unless told to clear it', () {
    final pinned = message('1', pinnedAt: at);
    expect(pinned.copyWith(text: 'edited').pinnedAt, at);
    expect(pinned.copyWith(clearPinned: true).pinnedAt, isNull);
  });

  test('a pinned message starts its own group, so its pin is drawn', () {
    // The pin is in the header, and only the first row of a group has one.
    expect(message('1').groupKey, isNot(message('2', pinnedAt: at).groupKey));
  });

  test('nothing locked, pending or private to one reader can be pinned', () {
    expect(MessagePermissions.canPin(message('1')), isTrue);
    expect(MessagePermissions.canPin(message('1', locked: true)), isFalse);
    expect(MessagePermissions.canPin(message('1', pending: true)), isFalse);
    expect(MessagePermissions.canPin(message('1', ephemeral: true)), isFalse);
  });

  test('the cap refusal is said in words', () {
    expect(PinOps.errorFor('P0001: pin_limit'), contains('${PinOps.maxPins}'));
    expect(PinOps.errorFor('P0001: cannot_pin'), contains('permission'));
    expect(PinOps.errorFor('P0001: not_friends'), contains('friend'));
    expect(PinOps.errorFor('timeout'), isNull);
  });
}
