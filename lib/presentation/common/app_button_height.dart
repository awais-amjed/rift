import 'package:flutter/widgets.dart';

/// The height every [AppButton] below takes unless it was given one.
///
/// For a group whose buttons are all a size other than the app's shared
/// control height — a member's moderation actions, compact inside a row on a
/// desktop. Rather than every button in it being passed a height — and one
/// forgetting — the group says it once, here, and the buttons follow.
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
