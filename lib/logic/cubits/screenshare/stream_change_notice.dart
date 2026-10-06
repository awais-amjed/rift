import '../../../data/classes/screen_share_settings.dart';

/// The toast that tells the sharer a change to their running share went
/// through — viewers see the picture blink, the sharer otherwise sees nothing.
/// [now] is the share's settings after the change; the flags say which one
/// menu pick it was. [fpsLowered] is a bigger picture taking the frame rate
/// down with it, from 120 to 60, which the sharer did not ask for and so is
/// told about.
({String title, String description}) streamChangeNotice({
  required ScreenShareSettings now,
  bool fpsChanged = false,
  bool fpsLowered = false,
  bool soundChanged = false,
}) {
  if (soundChanged) {
    return (
      title: now.shareAudio ? 'Stream sound on' : 'Stream sound off',
      description: now.shareAudio
          ? 'Viewers can hear it'
          : 'Viewers no longer hear it',
    );
  }
  if (fpsChanged) {
    return (title: 'Frame rate updated', description: '${now.fps} fps');
  }
  return (
    title: 'Stream quality updated',
    description: fpsLowered
        ? '${now.resolutionLabel} · ${now.fps} fps'
        : now.resolutionLabel,
  );
}
