import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/chat/attachments/video/widgets/video_controls.dart';

void main() {
  test('a video clock counts minutes, then hours', () {
    expect(VideoControls.clock(Duration.zero), '0:00');
    expect(VideoControls.clock(const Duration(seconds: 75)), '1:15');
    expect(
      VideoControls.clock(const Duration(minutes: 59, seconds: 9)),
      '59:09',
    );
    expect(
      VideoControls.clock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
