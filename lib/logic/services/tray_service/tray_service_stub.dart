/// The web's tray: there is none, and the tab is the way back to itself.
class TrayService {
  TrayService._();

  static final TrayService instance = TrayService._();

  bool get isShowing => false;

  Future<void> init() async {}
}
