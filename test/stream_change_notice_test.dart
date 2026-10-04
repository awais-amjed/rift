import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/logic/cubits/screenshare/stream_change_notice.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

void main() {
  const asked720 = ScreenShareSettings(resolution: 720, fps: 30);

  ShareStatus sent({int? width, int? height, bool audio = false}) =>
      ShareStatus(width: width, height: height, fps: 30, shareAudio: audio);

  test('says the size that goes out, not the one picked', () {
    final notice = streamChangeNotice(
      asked: asked720,
      sent: sent(width: 1280, height: 720),
      soundChanged: false,
    );
    expect(notice.title, 'Stream quality changed');
    expect(notice.description, 'Now sending 1280×720 at 30 fps.');
  });

  test('explains a picture sent below the height picked', () {
    final notice = streamChangeNotice(
      asked: const ScreenShareSettings(resolution: 1080, fps: 30),
      sent: sent(width: 960, height: 1000),
      soundChanged: false,
    );
    expect(notice.description, startsWith('Now sending 960×1000 at 30 fps.'));
    expect(notice.description, contains('not scaled up'));
  });

  test('a share still waiting on its window says when it applies', () {
    final notice = streamChangeNotice(
      asked: asked720,
      sent: sent(),
      soundChanged: false,
    );
    expect(notice.description, contains('720p, 30 fps'));
    expect(notice.description, contains('open the window'));
  });

  test('a sound change speaks of sound, either way', () {
    expect(
      streamChangeNotice(
        asked: asked720,
        sent: sent(width: 1280, height: 720, audio: true),
        soundChanged: true,
      ).title,
      'Stream sound on',
    );
    expect(
      streamChangeNotice(
        asked: asked720,
        sent: sent(width: 1280, height: 720),
        soundChanged: true,
      ).title,
      'Stream sound off',
    );
  });
}
