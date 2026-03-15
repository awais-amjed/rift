/// No-op stub used on web where dart:io / win32 are unavailable.
class WindowsAudioDucking {
  static void disable() {}
  static void restore() {}
  static void apply({required bool disable}) {}
}

