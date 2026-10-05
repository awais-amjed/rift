import '../../src/rust/api/screenshare.dart';
import '../../src/rust/api/screenshare/types.dart';
import '../helper_methods.dart';
import 'host_platform.dart';

/// What this computer's GPU can encode a screen share in, asked of Rust once.
///
/// Opening an encoder to find out takes a moment, so it is asked at startup
/// ([warmUp]) and the share dialog reads [known], which is empty until then
/// and wherever Rust does not choose the encoder itself.
class GpuCodecs {
  const GpuCodecs._();

  static Future<Set<VideoCodec>>? _asked;

  /// The answer once it is in; empty before that.
  static Set<VideoCodec> known = const {};

  /// The answer, asked for the first time if need be.
  static Future<Set<VideoCodec>> get supported => _asked ??= _ask();

  /// Start asking, without waiting for the answer.
  static void warmUp() => supported;

  static Future<Set<VideoCodec>> _ask() async {
    if (!HostPlatform.isDesktop) return const {};
    try {
      known = (await gpuVideoCodecs()).toSet();
    } catch (e) {
      HelperMethods.printDebug('GPU codecs: $e');
    }
    return known;
  }
}
