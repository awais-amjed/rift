//! Where Rift looks for releases: its GitHub releases, accepting a release's
//! feed only when the release key signed it (see `signature`).
//!
//! Velopack's own `GithubSource` reads the same releases, but trusts each
//! feed as it finds it; this is that source with the check added, and with
//! each package fetched from the release whose signed feed listed it, by the
//! download the person can pause (`transfer`).
//!
//! A check reads the list of releases, then the feed and signature of each
//! release newer than the installed one, and no others: those are all a
//! chain of deltas from here needs, so a check finding nothing new is one
//! request. The whole check has [CHECK_LIMIT]: a slow GitHub once left it on
//! "Checking…" for minutes, each of its many requests waiting its own 30 s.

use std::collections::HashMap;
use std::path::Path;
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use semver::Version;
use serde::Deserialize;
use velopack::bundle::Manifest;
use velopack::sources::UpdateSource;
use velopack::{Error, VelopackAsset, VelopackAssetFeed};

use super::signature;
use super::transfer::Transfer;

/// The public repository the release workflow publishes to. Thirty, so that
/// a run of betas does not hide the last stable from someone without them;
/// only those newer than the installed version are read further.
const RELEASES_API: &str = "https://api.github.com/repos/awais-amjed/rift/releases?per_page=30";

/// A folder of releases to read instead of GitHub, for trying an update out
/// before publishing it. Its feeds must be signed all the same.
const FEED_OVERRIDE: &str = "RIFT_UPDATE_FEED";

/// How long a whole check may take, every request in it together.
const CHECK_LIMIT: Duration = Duration::from_secs(60);

#[derive(Deserialize)]
struct GithubRelease {
    #[serde(default)]
    tag_name: String,
    prerelease: bool,
    draft: bool,
    #[serde(default)]
    assets: Vec<GithubAsset>,
}

#[derive(Deserialize)]
struct GithubAsset {
    name: String,
    browser_download_url: String,
}

/// One release's files: a listing (a GitHub release), or a folder in which
/// any name is a file.
enum Files {
    Listed(HashMap<String, String>),
    Folder(String),
}

impl Files {
    fn url(&self, name: &str) -> Option<String> {
        match self {
            Files::Listed(urls) => urls.get(name).cloned(),
            Files::Folder(base) => Some(format!("{}/{name}", base.trim_end_matches('/'))),
        }
    }
}

/// A release's version from its tag (`v2.1.0-beta.1`); `None` for a tag
/// that is not one, which is then read like any newer release.
fn tag_version(tag: &str) -> Option<Version> {
    Version::parse(tag.strip_prefix('v').unwrap_or(tag)).ok()
}

fn too_slow() -> Error {
    Error::Other(format!(
        "the releases did not answer within {} s",
        CHECK_LIMIT.as_secs()
    ))
}

/// A text file, or `None` when the server has no such file. Anything else —
/// no answer, a slow one, a server's error — fails the check: passing a
/// release over for it would answer "up to date" with a newer one out.
fn fetch_text(url: &str, accept: Option<&str>, deadline: Instant) -> Result<Option<String>, Error> {
    let left = deadline.saturating_duration_since(Instant::now());
    if left.is_zero() {
        return Err(too_slow());
    }
    let config = ureq::Agent::config_builder().timeout_global(Some(left));
    // The tests' server is on this machine, where a proxy named in the
    // environment cannot reach it.
    #[cfg(test)]
    let config = if url.starts_with("http://127.0.0.1") {
        config.proxy(None)
    } else {
        config
    };
    let agent: ureq::Agent = config.build().into();
    let mut request = agent.get(url).header("User-Agent", "Rift");
    if let Some(accept) = accept {
        request = request.header("Accept", accept);
    }
    let read = request
        .call()
        .and_then(|mut response| response.body_mut().read_to_string());
    match read {
        Ok(text) => Ok(Some(text)),
        Err(ureq::Error::StatusCode(404)) => Ok(None),
        Err(ureq::Error::Timeout(_)) => Err(too_slow()),
        Err(e) => Err(e.into()),
    }
}

pub(crate) struct SignedSource {
    include_prereleases: bool,
    /// Where the list of releases is read: GitHub's, but for the tests.
    listing: String,
    /// Each package the last feed listed, and where to fetch it from.
    packages: Mutex<HashMap<String, String>>,
    transfer: Arc<Transfer>,
}

impl SignedSource {
    pub(crate) fn new(include_prereleases: bool, transfer: Arc<Transfer>) -> Self {
        SignedSource {
            include_prereleases,
            listing: RELEASES_API.to_string(),
            packages: Mutex::new(HashMap::new()),
            transfer,
        }
    }

    /// The releases newer than `installed`, the newest first, as GitHub
    /// lists them.
    fn releases(&self, installed: &Version, deadline: Instant) -> Result<Vec<Files>, Error> {
        if let Ok(folder) = std::env::var(FEED_OVERRIDE) {
            return Ok(vec![Files::Folder(folder)]);
        }
        let json = fetch_text(&self.listing, Some("application/vnd.github+json"), deadline)?
            .ok_or_else(|| Error::Other(format!("{} is not there", self.listing)))?;
        let releases: Vec<GithubRelease> = serde_json::from_str(&json)?;
        Ok(releases
            .into_iter()
            .filter(|r| !r.draft && (self.include_prereleases || !r.prerelease))
            .filter(|r| tag_version(&r.tag_name).is_none_or(|v| v > *installed))
            .map(|r| {
                Files::Listed(
                    r.assets
                        .into_iter()
                        .map(|a| (a.name, a.browser_download_url))
                        .collect(),
                )
            })
            .collect())
    }

    fn read_feed(
        &self,
        channel: &str,
        installed: &Version,
        deadline: Instant,
    ) -> Result<VelopackAssetFeed, Error> {
        let feed_name = format!("releases.{channel}.json");
        let mut assets = Vec::new();
        let mut packages = HashMap::new();
        for files in self.releases(installed, deadline)? {
            let (Some(feed_url), Some(signature_url)) = (
                files.url(&feed_name),
                files.url(&format!("{feed_name}.sig")),
            ) else {
                continue;
            };
            // A release without a feed for this channel, or not signed yet,
            // is passed over rather than failing the check: the next one
            // down may still be newer than what is installed.
            let Some(feed) = fetch_text(&feed_url, None, deadline)? else {
                continue;
            };
            let Some(signature_text) = fetch_text(&signature_url, None, deadline)? else {
                continue;
            };
            if !signature::verify(
                channel,
                feed.as_bytes(),
                &signature_text,
                signature::RELEASE_KEYS,
            ) {
                log::warn!("updater: {feed_url} is not signed by the release key; skipped");
                continue;
            }
            let Ok(feed) = serde_json::from_str::<VelopackAssetFeed>(&feed) else {
                log::warn!("updater: {feed_url} is signed but unreadable; skipped");
                continue;
            };
            for asset in feed.Assets {
                if let Some(url) = files.url(&asset.FileName) {
                    // A package listed by two releases is the same file; the
                    // newer release's copy wins.
                    if !packages.contains_key(&asset.FileName) {
                        packages.insert(asset.FileName.clone(), url);
                        assets.push(asset);
                    }
                }
            }
        }
        *self.packages.lock().unwrap() = packages;
        Ok(VelopackAssetFeed { Assets: assets })
    }
}

impl UpdateSource for SignedSource {
    fn get_release_feed(
        &self,
        channel: &str,
        app: &Manifest,
        _staged_user_id: &str,
    ) -> Result<VelopackAssetFeed, Error> {
        self.read_feed(channel, &app.version, Instant::now() + CHECK_LIMIT)
    }

    /// Velopack's progress goes unused: the transfer counts bytes, and a
    /// delta's download is given no progress at all.
    fn download_release_entry(
        &self,
        asset: &VelopackAsset,
        local_file: &Path,
        _progress: Option<Sender<i16>>,
    ) -> Result<(), Error> {
        let url = self
            .packages
            .lock()
            .unwrap()
            .get(&asset.FileName)
            .cloned()
            .ok_or_else(|| {
                Error::Other(format!(
                    "{} is in no signed feed read so far",
                    asset.FileName
                ))
            })?;
        // Velopack checks the file against the feed's size and SHA-256 once
        // it is down, and throws it away if either is off.
        self.transfer.fetch(&url, asset, local_file)
    }
}

#[cfg(test)]
mod tests {
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;

    use super::*;

    /// A server answering each path in `routes` with a status, a body and a
    /// wait before answering; any other path is a 404. Returns its address
    /// and the paths asked for.
    fn serve(routes: Vec<(&'static str, u16, String, u64)>) -> (String, Arc<Mutex<Vec<String>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let asked = Arc::new(Mutex::new(Vec::new()));
        let log = asked.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { return };
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut first = String::new();
                let _ = reader.read_line(&mut first);
                loop {
                    let mut line = String::new();
                    if reader.read_line(&mut line).unwrap_or(0) == 0 || line == "\r\n" {
                        break;
                    }
                }
                let path = first.split_whitespace().nth(1).unwrap_or("").to_string();
                log.lock().unwrap().push(path.clone());
                let (status, body, wait) = routes
                    .iter()
                    .find(|r| r.0 == path)
                    .map(|r| (r.1, r.2.clone(), r.3))
                    .unwrap_or((404, String::new(), 0));
                // Answered on a thread of its own, so a slow path holds up
                // nothing else.
                std::thread::spawn(move || {
                    std::thread::sleep(Duration::from_millis(wait));
                    let head = format!(
                        "HTTP/1.1 {status} X\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    let _ = stream.write_all(head.as_bytes());
                    let _ = stream.write_all(body.as_bytes());
                });
            }
        });
        (base, asked)
    }

    /// A GitHub listing of `tags`, newest first, each with a Linux feed and
    /// signature on the same server.
    fn listing(base: &str, tags: &[&str]) -> String {
        let releases: Vec<_> = tags
            .iter()
            .map(|tag| {
                serde_json::json!({
                    "tag_name": tag,
                    "prerelease": tag.contains('-'),
                    "draft": false,
                    "assets": [
                        {"name": "releases.linux.json",
                         "browser_download_url": format!("{base}/{tag}/feed")},
                        {"name": "releases.linux.json.sig",
                         "browser_download_url": format!("{base}/{tag}/sig")},
                    ],
                })
            })
            .collect();
        serde_json::to_string(&releases).unwrap()
    }

    fn source(base: &str, betas: bool) -> SignedSource {
        SignedSource {
            listing: format!("{base}/releases"),
            ..SignedSource::new(betas, Arc::new(Transfer::new()))
        }
    }

    fn version(text: &str) -> Version {
        Version::parse(text).unwrap()
    }

    fn soon() -> Instant {
        Instant::now() + Duration::from_secs(10)
    }

    #[test]
    fn a_tag_names_its_version() {
        assert_eq!(tag_version("v2.1.0-beta.1"), Some(version("2.1.0-beta.1")));
        assert_eq!(tag_version("1.5.2"), Some(version("1.5.2")));
        assert_eq!(tag_version("nightly"), None);
    }

    /// A server of feeds, and a listing of `tags` on a second one pointing
    /// at it, since the listing has to name the first one's address.
    fn releases(
        tags: &[&str],
        files: Vec<(&'static str, u16, String, u64)>,
    ) -> (String, Arc<Mutex<Vec<String>>>, Arc<Mutex<Vec<String>>>) {
        let (files, files_asked) = serve(files);
        let (lists, lists_asked) = serve(vec![("/releases", 200, listing(&files, tags), 0)]);
        (lists, lists_asked, files_asked)
    }

    fn asked(log: &Arc<Mutex<Vec<String>>>) -> Vec<String> {
        log.lock().unwrap().clone()
    }

    #[test]
    fn nothing_newer_is_one_request() {
        let (lists, lists_asked, files_asked) =
            releases(&["v2.0.0", "v2.0.0-beta.1", "v1.5.2"], Vec::new());
        let feed = source(&lists, true)
            .read_feed("linux", &version("2.0.0"), soon())
            .unwrap();
        assert!(feed.Assets.is_empty());
        assert_eq!(asked(&lists_asked), vec!["/releases"]);
        assert!(asked(&files_asked).is_empty());
    }

    #[test]
    fn only_newer_releases_are_read() {
        let ok = |path| (path, 200, "{}".to_string(), 0);
        let (lists, _, files_asked) = releases(
            &["v2.1.0-beta.1", "v2.0.0", "v1.5.2", "v1.5.1"],
            vec![ok("/v2.0.0/feed"), ok("/v2.0.0/sig")],
        );
        source(&lists, false)
            .read_feed("linux", &version("1.5.2"), soon())
            .unwrap();
        // The beta is left out without betas, and 1.5.2 and older are not
        // newer than what is installed.
        assert_eq!(asked(&files_asked), vec!["/v2.0.0/feed", "/v2.0.0/sig"]);
    }

    #[test]
    fn a_missing_feed_is_passed_over() {
        let (lists, _, files_asked) = releases(&["v2.0.0"], Vec::new());
        let feed = source(&lists, false)
            .read_feed("linux", &version("1.5.2"), soon())
            .unwrap();
        assert!(feed.Assets.is_empty());
        assert_eq!(asked(&files_asked), vec!["/v2.0.0/feed"]);
    }

    #[test]
    fn a_slow_release_fails_the_check_in_time() {
        let (lists, _, _) = releases(
            &["v2.0.0"],
            vec![("/v2.0.0/feed", 200, "{}".to_string(), 5_000)],
        );
        let started = Instant::now();
        let error = source(&lists, false)
            .read_feed(
                "linux",
                &version("1.5.2"),
                Instant::now() + Duration::from_millis(500),
            )
            .unwrap_err();
        assert!(error.to_string().contains("did not answer"), "{error}");
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn a_server_error_fails_the_check() {
        let (lists, _, _) = releases(&["v2.0.0"], vec![("/v2.0.0/feed", 502, String::new(), 0)]);
        assert!(source(&lists, false)
            .read_feed("linux", &version("1.5.2"), soon())
            .is_err());
    }

    /// GitHub's real releases, from 2.0.0 with betas: what is newer, read
    /// within the limit. Prints the versions the signed feeds offered.
    #[test]
    #[ignore]
    fn a_real_check() {
        let started = Instant::now();
        let feed = SignedSource::new(true, Arc::new(Transfer::new()))
            .read_feed("linux", &version("2.0.0"), Instant::now() + CHECK_LIMIT)
            .unwrap();
        let mut found: Vec<_> = feed.Assets.iter().map(|a| a.Version.clone()).collect();
        found.dedup();
        println!("offered {found:?} in {:?}", started.elapsed());
    }
}
