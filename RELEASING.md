# Releasing

A release is a version tag pushed to Forgejo. In short:

```bash
scripts/release.sh 1.0.3          # sets the version, commits, tags; opens an editor for the notes
git push origin HEAD v1.0.3       # the tag starts the build
scripts/sign_release.sh v1.0.3    # once it is published: lets installed copies update to it
```

The version lives in one place, `pubspec.yaml`: in `1.0.3+4`, `1.0.3` is the
version people see and `4` a build number that only goes up.
`scripts/release.sh 1.0.3` moves both, commits, and tags `v1.0.3` with the
release notes as the tag's message. A version with a `-` (`1.1.0-beta.1`) is a
pre-release.

The tag, pushed to Forgejo, reaches the GitHub mirror, where
`.github/workflows/release.yml` builds the release and publishes it as a
GitHub Release (a pre-release is not marked latest). Velopack's `vpk` packs
each platform (`scripts/vpk_pack.sh`):

- `Rift-<version>-windows-x64-setup.exe`, the installer. It puts Rift in the
  person's own folder (`%LocalAppData%\CodingFries.Rift`), with no
  administrator prompt. It is not signed yet, so SmartScreen warns before it
  runs — once: an update is downloaded by Rift, not a browser, and is not
  checked.
- `rift-<version>-linux-x64.AppImage`, the one file to download and run. Its
  runtime carries its own FUSE, so it needs only `fusermount`, which nearly
  every system has.
- `CodingFries.Rift-<version>[-linux]-full.nupkg` and `-delta.nupkg`, the
  update packages, and `releases.win.json` / `releases.linux.json`, the feeds
  installed copies read. The delta is made against the newest release of the
  same kind (a pre-release for a pre-release), fetched first.
- `rift-<version>-linux-x64.tar.gz`, the bundle to unpack and run, which
  cannot update itself. It is built
  on Ubuntu 24.04 and needs that system's glibc, 2.39, or newer: Debian 13,
  Fedora 40, Mint 22 and the rolling distributions. It cannot be built lower:
  the image classifier's prebuilt runtime needs glibc 2.38, and an older
  system would start the app and lose the sensitive-image check without
  saying so. It uses GTK 3, libsecret, GStreamer, PulseAudio (PipeWire's
  stands in) and Ayatana AppIndicator from the system.
- `rift-<version>-android.apk`, the APK the website offers, holding both ARM
  ABIs so nobody has to pick one; `rift-<version>-android-<abi>.apk` for
  arm64-v8a, armeabi-v7a and x86_64, for whoever knows which they need; and
  `rift-<version>-android.aab`, the app bundle Google Play takes, with all
  three. Built by `scripts/build_android.sh`, every APK with the same
  versionCode, so any of them updates any other and Play's build updates
  them all. These are not published by the workflow: it has no keystore, so
  Gradle signs them with the debug key, and they wait with the run until
  `scripts/sign_release.sh` signs them (below). An APK does not update
  itself; Play installs are updated by Play. The build writes
  `android/app/google-services.json` from the `GOOGLE_SERVICES_JSON` secret
  (the file, base64), since the file is gitignored and the Google services
  plugin will not build without it.

Not published, and kept with the run for as long as GitHub keeps a run's
artifacts: `windows-symbols`, the FFmpeg library's linker map
(`rift_ffenc.map`) and the Rust library's PDB from that exact build. A crash in
someone's log gives offsets into those libraries (`ARCHITECTURE.md` §9), and
only the same build's map or PDB turns them into function names, so download
it from the release's run when a report needs it.

Run by hand from the Actions tab, the workflow builds the same files and keeps
them with the run instead of publishing anything. It was first run that way on
Oct 3 2026, before Velopack: both files built (Linux in 16 minutes, Windows in
31), and the Linux archive started on Manjaro.

## Signing a release

A feed is published unsigned, and an installed copy ignores a feed without
a valid signature, so nobody is offered a release until it is signed (see
`ARCHITECTURE.md` §8). Once the workflow has published it:

```bash
scripts/sign_release.sh v1.0.3
```

It shows what each feed offers, asks, signs with the release key from the
system keyring, checks the signature and uploads `releases.<channel>.json.sig`
beside the feed. It needs `gh` signed in to the GitHub account.

It signs the Android build in the same pass. It downloads the APKs and the
bundle from the release's workflow run, signs them with the keystore that
`android/key.properties` names (a symlink to where the keystore lives),
attaches the APKs to the release, and leaves the bundle in `build/release/`
for Google Play. If the run kept them but they will not download, it stops before
signing anything; run it again. It finds `apksigner` in the newest Android build tools and the
JDK Flutter uses. On Play this key is only the upload key: Play signs what
it installs with an app signing key Google generated at the first upload.
So a Play install and a GitHub APK cannot update one another (moving
between them means uninstalling), and `assetlinks.json` in `rift-website`
names both fingerprints. Play allows an app signing key upgrade once a year,
from Oct 17 2027 for this app, which could move Play to this key.

Given what Play shows under "What's new", it puts the bundle on Play too
(`scripts/play_upload.sh`): a beta on open testing, where it reaches the
testers once Google has reviewed it, and a release on production as a draft,
to be sent for review in Play Console by hand, since that one reaches
everybody. The notes are plain English text of at most 500 characters,
written for Android, and are checked before anything is signed:

```bash
scripts/sign_release.sh v1.0.3 --play-notes play-notes.txt
```

It signs in as a Google service account invited in Play Console's Users and
permissions with leave to release Rift, whose JSON key is kept in the keyring:

```bash
secret-tool store --label='Rift Play upload' service rift-play-upload < key.json
```

`scripts/play_upload.sh check` signs in and lists what each track holds,
changing nothing (first run Oct 24 2026; no bundle uploaded through it yet).
Without `--play-notes` the bundle is left for a manual upload.

Then it posts the release notes, betas too, to a Rift channel through a
webhook, since signing is when people can have the release. The webhook's URL
is kept in the keyring, as it holds the webhook's secret:

```bash
secret-tool store --label='Rift release webhook' service rift-release-webhook
```

It posts the same notes to a Discord channel through that channel's webhook,
kept the same way:

```bash
secret-tool store --label='Rift Discord webhook' service rift-discord-webhook
```

Discord draws markdown, so its copy keeps the notes' bold and code, pings
nobody and shows no link previews. A webhook missing from the keyring is
skipped. `scripts/sign_release.sh --announce v1.0.3` posts a release's
announcement on its own, and `--announce v1.0.3 discord` (or `rift`) to one
place only. First posted to Discord with 1.5.0-beta.11 (Oct 17 2026).

The key was made once with `scripts/release_key.sh generate` (Oct 6 2026). Its
public half is in `RELEASE_KEYS` in `rust/src/updater/signature.rs`. If the
key is lost, no installed copy can be updated again without a reinstall, so
keep an offline backup: `scripts/release_key.sh export <file>` seals it with a
passphrase, and `import` puts it back in a keyring.

## Trying an update before publishing it

Installed copies read GitHub unless `RIFT_UPDATE_FEED` names a folder served
over HTTP, whose feeds must be signed all the same:

```bash
VERSION=1.5.0-test.1 scripts/vpk_pack.sh linux build/linux/x64/release/bundle
# install build/release/rift-1.5.0-test.1-linux-x64.AppImage, then pack a
# newer version into a folder, sign it, serve it:
scripts/sign_release.sh --dir <folder>
python3 -m http.server -d <folder> 8765
RIFT_UPDATE_FEED=http://127.0.0.1:8765 ./Rift.AppImage
```

## The move from the old installer

Releases before Velopack were Inno Setup installers into `C:\Program Files\Rift`,
which cannot update themselves: each person installs the first Velopack
release by hand. Its first start finds the old copy (its uninstall key,
`919df387-…_is1`) and runs the old uninstaller behind one administrator
prompt, before it registers the `rift://` scheme and notifications again. A
refused prompt is remembered and not asked again. Settings and servers live in
`%AppData%`, which neither install owns, so they carry over.

## The web app

The web app is on Cloudflare Pages, on the joinrift.app account: a release at
`web.joinrift.app` (the Pages project `rift-web`), a pre-release at
`beta-web.joinrift.app` (`rift-web-beta`), so a beta never reaches the people
using the web app. Pages cannot build Flutter, so `release.yml` builds it
(`scripts/build_web.sh`), attaches `rift-<version>-web.zip` to the release for
whoever hosts their own copy, and once the release is published deploys it to
the project its version belongs to. It needs two secrets on the GitHub mirror:
`CLOUDFLARE_API_TOKEN`, a token that may edit Pages and nothing else, and
`CLOUDFLARE_ACCOUNT_ID`. Unlike the desktop feeds it is not signed: it is live
the moment the run ends.

To deploy by hand, from a clean checkout of a commit that has been pushed, so
the deployment names it:

```bash
scripts/build_web.sh
wrangler pages deploy build/web --project-name rift-web --branch production
```

with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` set.

Flutter's file names carry no version, so browsers must ask for each file
again or a deploy reaches them half at a time. `web/_headers` (copied into the
build) says so, but on the joinrift.app zone the Browser Cache TTL replaces it
with four hours for `.js` and `.wasm`. A response-header Transform Rule on the
zone, "web app: revalidate every file", sets `Cache-Control: no-cache` for
both hosts after it. The workflow checks it after each deploy, and fails if
`https://<host>/main.dart.js` is served without `no-cache`.
