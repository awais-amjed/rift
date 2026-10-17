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

`web.joinrift.app` is the Pages project `rift-web` on the joinrift.app
Cloudflare account. Pages cannot build Flutter, so the build is made here and
uploaded:

```bash
scripts/build_web.sh
wrangler pages deploy build/web --project-name rift-web --branch production
```

with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` set. Deploy from a
clean checkout of a commit that has been pushed, so the deployment names it.

Flutter's file names carry no version, so browsers must ask for each file
again or a deploy reaches them half at a time. `web/_headers` (copied into the
build) says so, but on `web.joinrift.app` the zone's Browser Cache TTL replaces
it with four hours for `.js` and `.wasm`. A response-header Transform Rule on
the zone, "web app: revalidate every file", sets `Cache-Control: no-cache` for
that host after it. Check it after a deploy:
`curl -sI https://web.joinrift.app/main.dart.js` shows `no-cache`.
