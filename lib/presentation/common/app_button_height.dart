import 'package:flutter/widgets.dart';

/// The height every [AppButton] below takes unless it was given one.
///
/// A phone's footer calls to action are taller than the app's shared control
/// height, because they sit under a thumb. Rather than every footer passing a
/// height to every button — and one forgetting — the footer says it once, here,
/// and the buttons in it follow.
class AppButtonHeight extends InheritedWidget {
  final double height;

  const AppButtonHeight({
    super.key,
    required this.height,
    required super.child,
  });

  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppButtonHeight>()?.height;

  @override
  bool updateShouldNotify(AppButtonHeight old) => height != old.height;
}
