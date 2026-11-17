import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart' show Window;

/// GTK's own size of [window] (through its `GtkWindow*`), the
/// size `gtk_window_resize` takes, which nativeapi's content size does not
/// match on Linux (see `AppWindow.size`). Null where GTK is not loaded.
Size? gtkWindowSize(Window window) {
  final gtkWindow = window.nativeObject;
  final get = _getSize;
  if (get == null || gtkWindow == nullptr) return null;
  return using((alloc) {
    final w = alloc<Int32>();
    final h = alloc<Int32>();
    get(gtkWindow, w, h);
    return Size(w.value.toDouble(), h.value.toDouble());
  });
}

/// Resizes [window] to [size], in [gtkWindowSize]'s
/// terms. False where GTK is not loaded.
///
/// The default size too: under X11 the runner has realized the window
/// before Dart asks, and GTK maps a realized window at its default size,
/// forgetting a resize asked for in between.
bool setGtkWindowSize(Window window, Size size) {
  final gtkWindow = window.nativeObject;
  final resize = _resize;
  final setDefault = _setDefaultSize;
  if (resize == null || setDefault == null || gtkWindow == nullptr) {
    return false;
  }
  final w = size.width.round(), h = size.height.round();
  setDefault(gtkWindow, w, h);
  resize(gtkWindow, w, h);
  return true;
}

typedef _GetSizeC =
    Void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>);
typedef _GetSize = void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>);
typedef _ResizeC = Void Function(Pointer<Void>, Int32, Int32);
typedef _Resize = void Function(Pointer<Void>, int, int);

// The runner links GTK, so its symbols are in the process.
final _GetSize? _getSize = _orNull(
  () => DynamicLibrary.process().lookupFunction<_GetSizeC, _GetSize>(
    'gtk_window_get_size',
  ),
);

final _Resize? _setDefaultSize = _orNull(
  () => DynamicLibrary.process().lookupFunction<_ResizeC, _Resize>(
    'gtk_window_set_default_size',
  ),
);

final _Resize? _resize = _orNull(
  () => DynamicLibrary.process().lookupFunction<_ResizeC, _Resize>(
    'gtk_window_resize',
  ),
);

T? _orNull<T>(T Function() lookup) {
  try {
    return lookup();
  } on ArgumentError {
    return null;
  }
}
