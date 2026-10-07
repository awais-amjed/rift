/// Where an attachment being saved goes, on each platform.
///
/// A file being saved is handed over a piece at a time as it downloads and
/// opens (`AttachmentRepository.downloadTo`), so none of the three answers
/// below holds it whole:
///
///  - **A desktop** asks where with the system's save dialog first, then
///    writes beside that name and renames the file into place only once all
///    of it has checked out, so a failed download leaves nothing behind.
///  - **A phone** has no path it can write to: Android and iOS hand out a
///    place to save only through their own dialog, and that dialog copies
///    from a file. So the download goes to a scratch file first and the
///    dialog opens when it is complete.
///  - **The web** cannot write a file at all. The pieces are gathered into a
///    browser Blob — which the browser keeps on disk once it is large — and
///    handed to it as a download at the end.
///
/// The `dart:io` half is what native compiles against, so nothing here reaches
/// `dart:js_interop` off the web, nor `dart:io` on it.
library;

export 'save_target_io.dart'
    if (dart.library.js_interop) 'save_target_web.dart';
