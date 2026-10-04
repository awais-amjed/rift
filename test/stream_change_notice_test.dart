import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/logic/cubits/screenshare/stream_change_notice.dart';

void main() {
  const now = ScreenShareSettings(resolution: 1440, fps: 30, shareAudio: true);

  test('a resolution change names the new resolution', () {
    final notice = streamChangeNotice(now: now);
    expect(notice.title, 'Stream quality updated');
    expect(notice.description, '2K');
  });

  test('a frame rate change names the new rate', () {
    final notice = streamChangeNotice(now: now, fpsChanged: true);
    expect(notice.title, 'Frame rate updated');
    expect(notice.description, '30 fps');
  });

  test('a sound change says which way it went', () {
    expect(
      streamChangeNotice(now: now, soundChanged: true).title,
      'Stream sound on',
    );
    expect(
      streamChangeNotice(
        now: now.copyWith(shareAudio: false),
        soundChanged: true,
      ).title,
      'Stream sound off',
    );
  });
}
