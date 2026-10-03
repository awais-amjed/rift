# Releasing

A release is a version tag pushed to Forgejo. In short:

```bash
scripts/release.sh 1.0.3          # sets the version, commits, tags; opens an editor for the notes
git push origin HEAD v1.0.3       # the tag starts the build
```

The version lives in one place, `pubspec.yaml`: in `1.0.3+4`, `1.0.3` is the
version people see and `4` a build number that only goes up.
`scripts/release.sh 1.0.3` moves both, commits, and tags `v1.0.3` with the
release notes as the tag's message. A version with a `-` (`1.1.0-beta.1`) is a
pre-release.

The tag, pushed to Forgejo, reaches the GitHub mirror, where
`.github/workflows/release.yml` builds two files and publishes them as a
GitHub Release (a pre-release is not marked latest):

- `Rift-<version>-windows-x64-setup.exe`, the Inno Setup installer. It is not
  signed yet, so SmartScreen warns before it runs.
- `rift-<version>-linux-x64.tar.gz`, the bundle to unpack and run. It is built
  on Ubuntu 24.04 and needs that system's glibc, 2.39, or newer: Debian 13,
  Fedora 40, Mint 22 and the rolling distributions. It cannot be built lower:
  the image classifier's prebuilt runtime needs glibc 2.38, and an older
  system would start the app and lose the sensitive-image check without
  saying so. It uses GTK 3, libsecret, GStreamer, PulseAudio (PipeWire's
  stands in) and Ayatana AppIndicator from the system.

Run by hand from the Actions tab, the workflow builds both files and keeps them
with the run instead of publishing anything. It was first run that way on Oct 3
2026: both files built (Linux in 16 minutes, Windows in 31), and the Linux
archive started on Manjaro. The installer had not been installed yet.
