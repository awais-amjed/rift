cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "global_key_hook.cpp"
  "main.cpp"
  "seen_watch.cpp"
  "single_instance.cpp"
  "startup_guard.cpp"
  "stream_draw.cpp"
  "stream_draw_vs.hlsl"
  "stream_draw_ps.hlsl"
  "stream_texture.cpp"
  "tray_icon.cpp"
  "utils.cpp"
  "velopack_hooks.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# A watched share's picture is drawn with D3D11 (stream_draw.cpp). Its shaders
# are compiled at build time by MSBuild's own HLSL step, which finds the
# Windows SDK's fxc itself, into headers in the build directory: nothing looks
# for fxc on PATH, and no shader compiler is loaded at run time. The compiled
# objects stay in the intermediate directory, out of the release folder.
set(STREAM_SHADERS "${CMAKE_CURRENT_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY "${STREAM_SHADERS}")
set_source_files_properties("stream_draw_vs.hlsl" PROPERTIES
  VS_SHADER_TYPE Vertex
  VS_SHADER_VARIABLE_NAME kStreamDrawVs)
set_source_files_properties("stream_draw_ps.hlsl" PROPERTIES
  VS_SHADER_TYPE Pixel
  VS_SHADER_VARIABLE_NAME kStreamDrawPs)
set_source_files_properties("stream_draw_vs.hlsl" "stream_draw_ps.hlsl"
  PROPERTIES
  VS_SHADER_MODEL 5.0
  VS_SHADER_ENTRYPOINT main
  VS_SHADER_OUTPUT_HEADER_FILE "${STREAM_SHADERS}/%(Filename).h"
  VS_SHADER_OBJECT_FILE_NAME "$(IntDir)%(Filename).cso")
target_include_directories(${BINARY_NAME} PRIVATE "${STREAM_SHADERS}")
target_link_libraries(${BINARY_NAME} PRIVATE "d3d11.lib" "dxgi.lib")

# The noise models on the microphone (native/noise_filter). Dart finds its
# functions among the executable's exports.
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/noise_filter"
  "${CMAKE_BINARY_DIR}/noise_filter")
target_link_libraries(${BINARY_NAME} PRIVATE rift_noise_filter)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}/../native")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
