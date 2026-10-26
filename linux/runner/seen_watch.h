#ifndef RUNNER_SEEN_WATCH_H_
#define RUNNER_SEEN_WATCH_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Whether anybody can see Rift's window on Wayland, where GTK 3 never hears
// it minimised: xdg-shell has no minimised state, and the suspended state
// that replaced it is one GTK 3 does not read. So the app lifecycle stays
// resumed, and a watched stream's picture stayed on (CALLS.md, "Watching
// while Rift cannot be seen"). What the compositor does do is stop giving
// frames: GNOME leaves a window's frame requests unanswered while it is
// minimised or wholly covered. So the watch asks for one on Rift's surface
// twice a second; one unanswered for a second and a half means nobody can
// see Rift, and two answered close together that they can again. One alone
// is not enough: GNOME lets a single frame through a few seconds after it
// hides a window. GTK's frame clock cannot tell: a window drawn with OpenGL,
// as Flutter's is, ticks on at full rate while minimised.
//
// Answers on the `rift/window_seen` channel, as the Windows runner does
// (windows/runner/seen_watch.h), while Dart listens (AppSeenListener). On
// X11 it stays silent: there the lifecycle hears minimised, and a covered
// window is still asked for frames.
namespace rift {

// Opens the channel for |window|, whose view is |view|.
void WatchSeen(GtkWindow* window, FlView* view);

}  // namespace rift

#endif  // RUNNER_SEEN_WATCH_H_
