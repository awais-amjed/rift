#ifndef RUNNER_STARTUP_GUARD_H_
#define RUNNER_STARTUP_GUARD_H_

// Notices a start that never reached its first frame, and says why when
// RivaTuner Statistics Server is running.
//
// RTSS, which comes with MSI Afterburner, hooks every process that draws with
// Direct3D to put its overlay on it, by patching code in dxgi.dll. When a
// Windows update replaces dxgi.dll before RTSS catches up, the patch lands on
// the wrong bytes and the process dies inside dxgi.dll ("illegal
// instruction") while its window is still being set up. That is before Dart
// runs, so the app's log never opens, and to the person Rift simply never
// appears (Oct 18 2026, dxgi.dll 10.0.26100.9711). Nothing in Rift can undo
// the hook; only an RTSS profile can leave Rift out. So each start is marked,
// the mark is cleared at the first frame, and a start that finds the mark
// still there while RTSS runs says what to do before trying again.

// Call once this copy is the one that will run, before its window exists.
// Explains when the last start never finished and RTSS is running, then
// marks this start.
void CheckLastStartAndMark();

// Call at the first frame: this start finished.
void MarkStartFinished();

#endif  // RUNNER_STARTUP_GUARD_H_
