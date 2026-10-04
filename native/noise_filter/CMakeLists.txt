# A noise model on the microphone, inside libwebrtc's own audio processing.
# Linked into the runner on Linux and Windows; see noise_filter.h.
cmake_minimum_required(VERSION 3.14)
project(rift_noise_filter LANGUAGES C CXX)

set(RNNOISE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/rnnoise")

# Plain C with the SSE2 every x64 CPU has, no run-time dispatch, and none of
# the warnings the runner treats as errors: a 10 ms frame takes well under a
# tenth of a millisecond.
add_library(rnnoise STATIC
  "${RNNOISE_DIR}/src/celt_lpc.c"
  "${RNNOISE_DIR}/src/denoise.c"
  "${RNNOISE_DIR}/src/kiss_fft.c"
  "${RNNOISE_DIR}/src/nnet.c"
  "${RNNOISE_DIR}/src/nnet_default.c"
  "${RNNOISE_DIR}/src/parse_lpcnet_weights.c"
  "${RNNOISE_DIR}/src/pitch.c"
  "${RNNOISE_DIR}/src/rnn.c"
  "${RNNOISE_DIR}/src/rnnoise_data.c"
  "${RNNOISE_DIR}/src/rnnoise_tables.c"
)
target_include_directories(rnnoise
  PUBLIC "${RNNOISE_DIR}/include"
  PRIVATE "${RNNOISE_DIR}/src"
)
set_target_properties(rnnoise PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
  target_compile_options(rnnoise PRIVATE /W0)
  # MSVC never defines __SSE2__, and the plain-C path it would take instead
  # includes a header the release tarball does not ship. Every x64 CPU has
  # SSE2, and these make x86_arch_macros.h say so.
  target_compile_definitions(rnnoise PRIVATE _USE_MATH_DEFINES
    OPUS_X86_MAY_HAVE_SSE OPUS_X86_MAY_HAVE_SSE2)
else()
  target_compile_options(rnnoise PRIVATE -w -O2)
  target_link_libraries(rnnoise PRIVATE m)
endif()

add_library(rift_noise_filter STATIC
  "noise_filter.cc"
  "rate_converter.cc"
)
apply_standard_settings(rift_noise_filter)
set_target_properties(rift_noise_filter PROPERTIES POSITION_INDEPENDENT_CODE ON)
# flutter_webrtc's headers, read the way the plugin itself is built, since the
# filter reaches its audio processing through the plugin's shared instance.
target_compile_definitions(rift_noise_filter PRIVATE RTC_DESKTOP_DEVICE)
target_link_libraries(rift_noise_filter PRIVATE rnnoise flutter flutter_webrtc_plugin)
if(WIN32)
  target_compile_definitions(rift_noise_filter PRIVATE LIB_WEBRTC_API_DLL)
  target_link_libraries(rift_noise_filter PRIVATE flutter_wrapper_plugin)
else()
  # The plugin carries its own copy of Flutter's C++ wrapper on Linux.
  target_include_directories(rift_noise_filter PRIVATE
    "$<TARGET_PROPERTY:flutter_webrtc_plugin,SOURCE_DIR>/flutter/include")
  # The bundled libwebrtc headers use uint32_t without <cstdint>; the plugin
  # forces it in the same way.
  target_compile_options(rift_noise_filter PRIVATE -include cstdint)
endif()
