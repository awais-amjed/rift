import '../../../data/classes/screen_share_settings.dart';
import '../../../src/rust/api/screenshare/types.dart';

/// What to tell the sharer after a change to their running share went
/// through. Viewers see the picture blink; the sharer sees nothing at all
/// unless told, so this says what now goes out — read back from the share,
/// not echoed from the menu.
///
/// [asked] is the settings the change was made with, [sent] what the share
/// reports, and [soundChanged] which of the two the change was about: a
/// change is one pick in the menu, so it is one or the other.
({String title, String description}) streamChangeNotice({
  required ScreenShareSettings asked,
  required ShareStatus sent,
  required bool soundChanged,
}) {
  if (soundChanged) {
    return sent.shareAudio
        ? (
            title: 'Stream sound on',
            description: 'Viewers now hear what the shared app plays.',
          )
        : (
            title: 'Stream sound off',
            description: 'Viewers no longer hear the shared app.',
          );
  }

  final asking =
      '${ScreenShareSettings.labelFor(asked.resolution)}, '
      '${sent.fps} fps';
  final (width, height) = (sent.width, sent.height);
  if (width == null || height == null) {
    return (
      title: 'Stream quality changed',
      description: 'It starts at $asking when you open the window.',
    );
  }
  final sending = 'Now sending $width×$height at ${sent.fps} fps.';
  // Nothing is scaled up, so a window shorter than the height picked goes
  // out at its own size — which would otherwise read as the change failing.
  return (
    title: 'Stream quality changed',
    description: height < asked.resolution
        ? '$sending What you share is smaller than '
              '${ScreenShareSettings.labelFor(asked.resolution)}, '
              'so it is not scaled up.'
        : sending,
  );
}
