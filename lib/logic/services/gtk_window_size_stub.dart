import 'package:flutter/widgets.dart';

/// No GTK on the web: see `gtk_window_size_ffi.dart`.
Size? gtkWindowSize(Object gtkWindow) => null;

bool setGtkWindowSize(Object gtkWindow, Size size) => false;
