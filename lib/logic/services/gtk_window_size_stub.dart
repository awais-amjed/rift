import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart' show Window;

/// No GTK on the web: see `gtk_window_size_ffi.dart`. The web's [Window] has
/// no native object to hand over, which is why these take the window itself.
Size? gtkWindowSize(Window window) => null;

bool setGtkWindowSize(Window window, Size size) => false;
