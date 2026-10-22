import 'package:flutter/widgets.dart';

/// Whether something has dimmed the whole window: a dialog's barrier, a
/// sheet's, or the scrim behind the overlaid member list.
///
/// The title bar needs to know. It is painted above the navigator, so the dim
/// goes under it, not over it, and with no fill of its own its ink then sits
/// on the dimmed canvas: the light theme's grey on a grey that dark, and the
/// wordmark and window controls all but vanished behind every dialog.
class WindowDim {
  const WindowDim._();

  static final ValueNotifier<int> _routes = ValueNotifier(0);

  /// The overlaid member list's scrim, which is a widget rather than a route.
  static final ValueNotifier<bool> overlay = ValueNotifier(false);

  /// Fires whenever [isOn] may have changed.
  static final Listenable changes = Listenable.merge([_routes, overlay]);

  static bool get isOn => _routes.value > 0 || overlay.value;
}

/// Counts the routes on the root navigator that dim what is under them.
///
/// Only a visible barrier counts: an anchored panel or a context menu takes
/// taps with a transparent one and leaves the window as it was.
class WindowDimObserver extends NavigatorObserver {
  final Set<Route<dynamic>> _dimming = {};

  static bool _dims(Route<dynamic>? route) =>
      route is ModalRoute && (route.barrierColor?.a ?? 0) > 0;

  void _add(Route<dynamic>? route) {
    if (_dims(route) && _dimming.add(route!)) _publish();
  }

  void _drop(Route<dynamic>? route) {
    if (_dimming.remove(route)) _publish();
  }

  void _publish() => WindowDim._routes.value = _dimming.length;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _drop(oldRoute);
    _add(newRoute);
  }
}
