# ONNX Runtime, Microsoft's own CPU build, which the Rust crate opens at run
# time for DPDFNet, a noise model on the microphone (rust/src/dpdfnet.rs). It
# is not linked into that library: the static build brings its own protobuf
# and abseil, which clash with libwebrtc's. Microsoft's shared library exports
# only its C API.
#
# Downloaded once per build folder and checked against the release's SHA-256,
# then installed beside the app's other libraries under the name the crate
# looks for. Its licences ship in assets/licenses/onnxruntime.txt.
set(ONNXRUNTIME_VERSION "1.28.2")
set(ONNXRUNTIME_RELEASE
  "https://github.com/microsoft/onnxruntime/releases/download/v${ONNXRUNTIME_VERSION}")

# rift_bundle_onnxruntime(<archive> <sha256> <library in it> <installed name>)
function(rift_bundle_onnxruntime archive sha256 member installed)
  set(dir "${PROJECT_BINARY_DIR}/onnxruntime")
  set(download "${dir}/${archive}")
  if(NOT EXISTS "${download}")
    message(STATUS "Downloading ONNX Runtime ${ONNXRUNTIME_VERSION}")
    file(DOWNLOAD "${ONNXRUNTIME_RELEASE}/${archive}" "${download}.part"
      EXPECTED_HASH SHA256=${sha256} STATUS status)
    list(GET status 0 code)
    if(NOT code EQUAL 0)
      file(REMOVE "${download}.part")
      message(FATAL_ERROR "ONNX Runtime did not download: ${status}")
    endif()
    file(RENAME "${download}.part" "${download}")
  endif()
  file(ARCHIVE_EXTRACT INPUT "${download}" DESTINATION "${dir}"
    PATTERNS "*/${member}")
  file(GLOB library "${dir}/*/${member}")
  install(FILES "${library}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    RENAME "${installed}" COMPONENT Runtime)
endfunction()
