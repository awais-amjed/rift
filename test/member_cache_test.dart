import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/member_cache.dart';

ServerMember _member(String id, {String name = 'Ada'}) => ServerMember.fromJson(
  {'id': id, 'username': name.toLowerCase(), 'display_name': name},
);

void main() {
  test('a member is found on the server they were met on', () {
    final cache = MemberCache();
    final met = cache.remember('s1', [_member('u1')]);

    expect(met.single.id, 'u1');
    expect(cache.lookup('s1', 'u1')?.displayName, 'Ada');
    expect(cache.lookup('s2', 'u1'), isNull);
  });

  test('another server listing the same id does not replace them', () {
    final cache = MemberCache();
    cache.remember('s1', [_member('u1', name: 'Ada')]);
    cache.remember('s2', [_member('u1', name: 'Grace')]);

    expect(cache.lookup('s1', 'u1')?.displayName, 'Ada');
    expect(cache.lookup('s2', 'u1')?.displayName, 'Grace');
  });

  test('a newer read of somebody replaces the older one', () {
    final cache = MemberCache();
    cache.remember('s1', [_member('u1', name: 'Ada')]);
    cache.remember('s1', [_member('u1', name: 'Ada L')]);

    expect(cache.lookup('s1', 'u1')?.displayName, 'Ada L');
  });
}
