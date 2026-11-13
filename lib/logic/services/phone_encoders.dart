import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../../src/rust/api/screenshare/types.dart';
import '../helper_methods.dart';
import 'phone_share_publish.dart';

/// What an Android phone or a browser can encode a share in, asked of
/// libwebrtc each time: it answers at once, and it does not fall back by
/// itself to a codec it has from one it does not.
class PhoneEncoders {
  const PhoneEncoders._();

  /// Only VP8 if the encoders cannot be asked: a share in it rather than none.
  static Future<List<VideoCodec>> codecs() async {
    try {
      final caps = await rtc.getRtpSenderCapabilities('video');
      final encoders = [for (final c in caps.codecs ?? const []) c.mimeType];
      HelperMethods.printDebug('[LiveKit] Share encoders: $encoders');
      return PhoneShare.codecsOf(encoders.whereType<String>());
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] Share encoders unknown: $e');
      return const [VideoCodec.vp8];
    }
  }
}
