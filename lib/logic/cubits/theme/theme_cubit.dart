import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../presentation/theme/app_palette.dart';
import '../../../presentation/theme/custom_colors.dart';

part 'theme_cubit.g.dart';

part 'theme_state.dart';

/// Light, dark or whatever the system is doing, and which palette. Persisted.
///
/// This holds the *preference*. Widgets read the *result* through
/// `context.theme`, whose own `themeMode` is the brightness actually being
/// drawn — [ThemeMode.system] resolves before it gets there, so nothing below
/// has to think about it.
class ThemeCubit extends HydratedCubit<ThemeState> {
  ThemeCubit() : super(ThemeState());

  void setTheme(ThemeMode themeMode) {
    emit(state.copyWith(themeMode: themeMode));
  }

  void setPalette(String paletteId) {
    emit(state.copyWith(paletteId: paletteId));
  }

  /// Flip to the other brightness, leaving [ThemeMode.system] behind.
  ///
  /// [showing] is the brightness on screen right now, which is the only thing
  /// that knows what "the other one" means while the preference is System.
  void switchTheme({Brightness showing = Brightness.dark}) {
    emit(
      state.copyWith(
        themeMode: showing == Brightness.dark
            ? ThemeMode.light
            : ThemeMode.dark,
      ),
    );
  }

  @override
  ThemeState? fromJson(Map<String, dynamic> json) {
    return ThemeState.fromJson(json);
  }

  @override
  Map<String, dynamic>? toJson(ThemeState state) {
    return state.toJson();
  }
}
