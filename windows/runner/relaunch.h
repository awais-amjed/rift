#ifndef RUNNER_RELAUNCH_H_
#define RUNNER_RELAUNCH_H_

// Rift starting itself again, for when the window can no longer be drawn
// (gpu_watch.h).
//
// The new copy is started first, while this one can still start anything,
// and waits for this one to leave before it takes the single-instance lock:
// otherwise it finds this copy still running, hands it the launch and exits.
// It holds this process by a handle it inherits rather than by its id, which
// Windows can give to another process once this one has gone.

#include <string>

// What the new copy is told: the reason Dart reads (`GpuReset`), and the
// process to wait for, which only the runner reads.
static constexpr wchar_t kAfterGpuResetFlag[] = L"--after-gpu-reset";
static constexpr wchar_t kAfterExitFlag[] = L"--after-exit=";

// Starts another copy of this program with this one's arguments, out of sight
// when |minimized|, and told why. False when Windows would not start it.
bool RelaunchAfterExit(bool minimized);

// First thing at a start: when the copy before this one started it, waits for
// that copy to leave, and ends it when it is still there after a few seconds,
// since a window that cannot draw may not close cleanly either.
void WaitForEarlierCopy();

// Whether |argument| is for the runner alone, kept from Dart.
bool IsRunnerArgument(const std::string& argument);

#endif  // RUNNER_RELAUNCH_H_
