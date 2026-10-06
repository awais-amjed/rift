#ifndef RUNNER_VELOPACK_HOOKS_H_
#define RUNNER_VELOPACK_HOOKS_H_

// Rift is installed and updated by Velopack (rust/src/updater). Velopack
// runs the app itself with `--veloapp-<hook> <version>` at four moments —
// after install, before and after an update, before uninstall — and allows it
// a few seconds before killing it. Starting Flutter would spend those
// seconds, so the hooks are answered here, before anything else.
//
// True when this launch was such a hook: it has been handled, and main()
// returns at once.
bool HandleVelopackHook();

// Once, on the first start of a copy Velopack installed: removes the copy
// the old installer put in Program Files, which the new one does not replace.
// That uninstaller needs the administrator's prompt, which Windows shows
// before Rift's window. If the prompt is refused, it is not asked again.
void RemoveLegacyInstall();

// Gives the process the id the installer's shortcuts carry, so a pinned
// taskbar icon and the running window are one button. Only for a copy
// Velopack installed; a build run from its folder keeps Windows' own.
void ApplyInstalledAppUserModelId();

#endif  // RUNNER_VELOPACK_HOOKS_H_
