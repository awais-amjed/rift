#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <gtk/gtk.h>

// One running copy per profile, as on Windows (windows/runner/single_instance.h).
//
// Closing the window hides Rift in the tray, and GNOME, which knows an app by
// its windows, then takes it for closed: opening Rift from the app grid or a
// search starts a second copy. That copy cannot have the profile the first
// one holds (Hive locks hydrated_box.lock), so it stops before its window is
// shown, and nothing appears. So a second launch hands over to the running
// copy, which shows its window, and exits.
//
// The running copy listens on a socket in the user's runtime directory, named
// for the profile Dart resolves (StorageNamespace): RIFT_PROFILE when set,
// otherwise `dev` for a debug build and none for release. Copies on different
// profiles still run side by side.
namespace rift {

// True when this is the only copy on its profile. False when another copy is
// running: it has been asked to show itself, and this one should exit.
bool AcquireSingleInstance();

// Shows |window| each time a later launch asks for it.
void ListenForLaunches(GtkWindow* window);

}  // namespace rift

#endif  // RUNNER_SINGLE_INSTANCE_H_
