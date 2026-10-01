import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/toast_identity.dart';

/// Presses on a Windows notification are delivered to the COM class its
/// identity names. Profiles used to share the release one, so a press on one
/// profile's notification went to whichever had registered last.
void main() {
  test('the release identity is the installer\'s, unchanged', () {
    final release = ToastIdentity.forSuffix('');
    expect(release.appUserModelId, 'CodingFries.Rift');
    expect(release.guid, '919df387-f79b-5d74-bee3-b08f176b2a14');
    expect(release.appName, 'Rift');
  });

  test('each namespace gets an identity of its own, the same every run', () {
    final a = ToastIdentity.forSuffix('wa');
    final b = ToastIdentity.forSuffix('wb');
    final dev = ToastIdentity.forSuffix('dev');
    final guids = {a.guid, b.guid, dev.guid, ToastIdentity.forSuffix('').guid};
    expect(guids, hasLength(4));
    expect({a.appUserModelId, b.appUserModelId}, hasLength(2));
    expect(ToastIdentity.forSuffix('wa').guid, a.guid);
    for (final guid in guids) {
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(guid),
        isTrue,
        reason: guid,
      );
    }
  });

  test('a press that starts Rift starts the profile it was for', () {
    const exe = r'C:\Program Files\Rift\rift.exe';
    expect(ToastIdentity.launchCommand(exe), '"$exe"');
    expect(
      ToastIdentity.launchCommand(exe, profile: 'wa'),
      '"$exe" --rift-profile=wa',
    );
  });
}
