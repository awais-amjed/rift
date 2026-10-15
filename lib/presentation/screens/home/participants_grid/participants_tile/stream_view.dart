/// How a watched stream is on the screen.
enum StreamView {
  /// In the call, beside everything else.
  inCall,

  /// Alone in the window: the sidebars, header and call bar out of the way,
  /// the window left the size it was. For watching beside other windows.
  edgeToEdge,

  /// Alone on the monitor: the window goes full screen too.
  fullscreen;

  /// On the page of its own ([StreamFullscreenPage]) rather than in the call.
  bool get isAlone => this != inCall;
}
