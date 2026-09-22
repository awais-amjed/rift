import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';

/// `context.theme`: the [ThemeState] in scope.
///
/// Read off the `ThemeData` the app installed it on, so a widget no longer
/// has to be handed the theme by whoever built it. A test that pumps a bare
/// `MaterialApp` has no extension to read, so the cubit stands in there.
///
/// That fallback is a `read`, not a `watch`, so it never rebuilds anything.
/// Above the `MaterialApp` — in `main.dart`, which builds the theme — there
/// is no Theme yet, and the cubit has to be watched directly.
extension ThemeContext on BuildContext {
  ThemeState get theme =>
      Theme.of(this).extension<ThemeState>() ?? read<ThemeCubit>().state;
}
