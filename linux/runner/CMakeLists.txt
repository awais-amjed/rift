cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "seen_watch.cc"
  "single_instance.cc"
  "stream_texture.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# The window's own frame requests on Wayland (seen_watch.cc).
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WAYLAND_CLIENT)

# A watched share's shader, in Flutter's own GL context (stream_texture.cc).
# GTK already brings libepoxy in.
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::EPOXY)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# The noise models on the microphone (native/noise_filter). Dart finds its
# functions in the executable, so they go in its dynamic symbol table.
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/noise_filter"
  "${CMAKE_BINARY_DIR}/noise_filter")
target_link_libraries(${BINARY_NAME} PRIVATE rift_noise_filter)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}/../native")
target_link_options(${BINARY_NAME} PRIVATE
  "LINKER:--export-dynamic-symbol=rift_noise_filter_*")

# The system's C++ unwinder goes ahead of Flutter's. Flutter 3.50's engine
# exports a copy of LLVM's (_Unwind_RaiseException and the rest) and comes
# first in the load order, so every C++ library in the process threw through it,
# and an exception it cannot carry ends the app: Intel's VAAPI driver throws
# and catches one of its own inside vaCreateContext, and Rift died at start
# probing the GPU encoders. Naming libgcc_s before anything else on the link
# line makes it the first library the executable needs. A Rust panic caught
# inside the app aborted the same way. Upstream: flutter/flutter#196402, fixed
# by #196451 (open Nov 13 2026); drop this once a stable engine exports no
# _Unwind_ symbols (nm -D --defined-only libflutter_linux_gtk.so).
target_link_options(${BINARY_NAME} PRIVATE
  "LINKER:--push-state,--no-as-needed,-lgcc_s,--pop-state")
