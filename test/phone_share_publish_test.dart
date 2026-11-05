// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/utils.dart' show Utils;
import 'package:rift/logic/services/phone_share_publish.dart';

void main() {
  test('a phone with an H264 encoder shares in H264 at 30 fps and 5 Mbps', () {
    final options = phoneSharePublishOptions(['video/VP8', 'video/H264'])!;

    expect(options.videoCodec, 'h264');
    expect(options.screenShareEncoding!.maxFramerate, 30);
    expect(options.screenShareEncoding!.maxBitrate, 5000 * 1000);
  });

  test('the encoding reaches the sent picture, not only the options', () {
    final encodings = Utils.computeVideoEncodings(
      isScreenShare: true,
      dimensions: VideoDimensionsPresets.h1080_169,
      options: phoneSharePublishOptions(['video/H264']),
      codec: 'h264',
    )!;

    expect(encodings.last.maxFramerate, 30);
    expect(encodings.last.maxBitrate, 5000 * 1000);
  });

  test('a phone without one is left to the SDK, as it always was', () {
    expect(phoneSharePublishOptions(['video/VP8', 'video/VP9']), isNull);
    expect(phoneSharePublishOptions(const []), isNull);
  });
}
