//! Where Rift looks for releases: its GitHub releases, accepting a release's
//! feed only when the release key signed it (see `signature`).
//!
//! Velopack's own `GithubSource` reads the same releases, but trusts each
//! feed as it finds it; this is that source with the check added, and with
//! each package fetched from the release whose signed feed listed it.

use std::collections::HashMap;
use std::path::Path;
use std::sync::mpsc::Sender;
use std::sync::Mutex;

use serde::Deserialize;
use velopack::bundle::Manifest;
use velopack::download::{download_url_as_string, download_url_to_file};
use velopack::sources::UpdateSource;
use velopack::{Error, HttpHeader, HttpOptions, VelopackAsset, VelopackAssetFeed};

use super::signature;

/// The public repository the release workflow publishes to.
const RELEASES_API: &str = "https://api.github.com/repos/awais-amjed/rift/releases?per_page=10";

/// A folder of releases to read instead of GitHub, for trying an update out
/// before publishing it. Its feeds must be signed all the same.
const FEED_OVERRIDE: &str = "RIFT_UPDATE_FEED";

#[derive(Deserialize)]
struct GithubRelease {
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

pub(crate) struct SignedSource {
    include_prereleases: bool,
    /// Each package the last feed listed, and where to fetch it from.
    packages: Mutex<HashMap<String, String>>,
}

impl SignedSource {
    pub(crate) fn new(include_prereleases: bool) -> Self {
        SignedSource { include_prereleases, packages: Mutex::new(HashMap::new()) }
    }

    fn options(timeout_ms: u64) -> HttpOptions {
        HttpOptions {
            Headers: vec![HttpHeader { Name: "User-Agent".into(), Value: "Rift".into() }],
            TimeoutMilliseconds: timeout_ms,
        }
    }

    /// The newest releases first, as GitHub lists them.
    fn releases(&self) -> Result<Vec<Files>, Error> {
        if let Ok(folder) = std::env::var(FEED_OVERRIDE) {
            return Ok(vec![Files::Folder(folder)]);
        }
        let mut options = Self::options(30_000);
        options.Headers.push(HttpHeader {
            Name: "Accept".into(),
            Value: "application/vnd.github+json".into(),
        });
        let json = download_url_as_string(RELEASES_API, Some(&options))?;
        let releases: Vec<GithubRelease> = serde_json::from_str(&json)?;
        Ok(releases
            .into_iter()
            .filter(|r| !r.draft && (self.include_prereleases || !r.prerelease))
            .map(|r| {
                Files::Listed(r.assets.into_iter().map(|a| (a.name, a.browser_download_url)).collect())
            })
            .collect())
    }
}

impl UpdateSource for SignedSource {
    fn get_release_feed(&self, channel: &str, _app: &Manifest, _staged_user_id: &str) -> Result<VelopackAssetFeed, Error> {
        let feed_name = format!("releases.{channel}.json");
        let options = Self::options(30_000);
        let mut assets = Vec::new();
        let mut packages = HashMap::new();
        for files in self.releases()? {
            let (Some(feed_url), Some(signature_url)) = (files.url(&feed_name), files.url(&format!("{feed_name}.sig")))
            else {
                continue;
            };
            // A release without a feed for this channel, or not signed yet,
            // is passed over rather than failing the check: the next one
            // down may still be newer than what is installed.
            let (Ok(feed), Ok(signature_text)) = (
                download_url_as_string(&feed_url, Some(&options)),
                download_url_as_string(&signature_url, Some(&options)),
            ) else {
                continue;
            };
            if !signature::verify(channel, feed.as_bytes(), &signature_text, signature::RELEASE_KEYS) {
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

    fn download_release_entry(&self, asset: &VelopackAsset, local_file: &Path, progress: Option<Sender<i16>>) -> Result<(), Error> {
        let url = self.packages.lock().unwrap().get(&asset.FileName).cloned().ok_or_else(|| {
            Error::Other(format!("{} is in no signed feed read so far", asset.FileName))
        })?;
        // Velopack checks the file against the feed's size and SHA-256 once
        // it is down, and throws it away if either is off.
        download_url_to_file(&url, local_file, Some(&Self::options(30 * 60_000)), |p| {
            if let Some(progress) = &progress {
                let _ = progress.send(p);
            }
        })
    }
}
