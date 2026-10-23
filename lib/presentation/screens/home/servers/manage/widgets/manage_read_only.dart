import 'package:flutter/widgets.dart';

/// Marks the manage pages below it as view-only — a phone's server
/// management, where only Members stays editable.
///
/// The roles editor's permission grid, retention limits and listing details
/// are each one mistap from a change nobody meant, on a screen where the
/// reader can see a fraction of the page at once. Showing the current state
/// keeps them useful for checking; changing them waits for a bigger screen.
class ManageReadOnly extends InheritedWidget {
  const ManageReadOnly({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ManageReadOnly>() != null;

  @override
  bool updateShouldNotify(ManageReadOnly old) => false;
}
