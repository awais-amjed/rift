/// A file read as fixed-size chunks, the way a file sealed a chunk at a time
/// needs it.
///
/// Native code reads the chunks straight off the disk, a chunk per read.
/// `XFile.openRead` hands over 64 KB pieces, and each one is an event the UI
/// isolate has to take between frames: measured Oct 7, a 200 MB file took
/// 4.7 s to read that way inside the running app against 0.2 s alone. The web
/// has no path to read, so it streams the browser's file and re-cuts that.
library;

export 'file_chunks_io.dart'
    if (dart.library.js_interop) 'file_chunks_web.dart';
