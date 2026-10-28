# OMNI AI Media Streaming Architecture

## Decision

Build the OMNI AI media hub as our own UI and playback orchestration layer. Do not treat the ZONA website as a confirmed public API: no stable, documented public catalog/playback API has been verified. Opening ZONA externally is only a temporary handoff, not an in-app integration.

Separate the system into interfaces so the UI does not depend on a specific provider:

- `MediaCatalogProvider`: search and resolve real metadata (title, year, artwork, seasons/episodes, language tracks, source attribution).
- `TorrentSourceProvider`: accepts a user-provided magnet URI or torrent file, validates it, and exposes file/track metadata. It must not scrape protected services or silently locate copyrighted content.
- `StreamingEngine`: adds a torrent, selects a media file, reports buffer/cache progress, and returns a local HTTP/HLS playback URL.
- `MediaPlaybackController`: plays the returned URL and manages subtitles, audio selection, progress, and resume.
- `PlaybackHistoryRepository`: local history, favorites, and user-controlled cache cleanup.

## Engine options

### Option A — connect to an already running TorrServer

This is the fastest prototype path. OMNI AI can offer a server URL setting, a connection/health check, and a small adapter for the documented API. The server may run on the same device or another device on the user's trusted network.

Security requirements: warn that plain HTTP is unencrypted (especially for non-loopback hosts), do not put credentials in the URL or logs, do not expose an unauthenticated server to the public network, and never ship default credentials. The current settings prototype validates a root HTTP(S) URL and checks the documented `GET /echo` health endpoint. A successful health check confirms reachability only; it does not yet prove that playback works.

### Option B — bundle or embed a torrent engine

This can make playback feel integrated, but it is a larger Android/native integration task: ABI builds, lifecycle, storage/cache limits, foreground-service/background behavior, cleanup, device compatibility, and HTTP player integration all need validation. TorrServer is GPL-3.0; bundling or linking it may impose source-distribution and license obligations on the combined product. Review the license and distribution model before adding its binaries or code. Do not copy code before that review.

### Option C — embed libtorrent4j (preferred candidate for the standalone player)

The first library candidate is [libtorrent4j](https://github.com/aldenml/libtorrent4j), whose Java API wraps the native libtorrent engine and whose project declares the MIT license. Keep it as a candidate until an Android build proves the selected artifacts work together; a dependency declaration alone is not a working player.

**Android compatibility constraint:** the repository currently sets `minSdk = 26`. The upstream changelog states that `2.0.5-22` supports Android API 24 and newer, while the current `2.1.0-39` line requires API 28 or newer. Therefore, do not blindly select the newest release: first validate `2.0.5-22` against the app's Kotlin/Gradle toolchain and all target ABIs. The base artifact is `org.libtorrent4j:libtorrent4j:2.0.5-22`; native Android artifacts are published separately per ABI. See the [upstream changelog](https://github.com/aldenml/libtorrent4j/blob/master/changelog.txt) and [Maven Central artifact listing](https://central.sonatype.com/artifact/org.libtorrent4j/libtorrent4j).

Required implementation slices, in order:

1. Add a native session owner with serialized start/stop, no blocking native shutdown on the UI thread, and a single shared session rather than one session per episode.
2. Add a Flutter platform channel for open/status/cancel/close. Validate magnet hashes before crossing the channel; never log the complete magnet URI.
3. Resolve metadata and expose the real file list. Select an episode only on an unambiguous season/episode match; otherwise return the candidate list for an explicit in-app choice.
4. Prioritize the selected file and implement a loopback HTTP server with correct byte-range responses so `video_player` can seek without copying the entire video first.
5. Add buffer/readiness timeouts, cancellation, process/activity lifecycle handling, bounded cache and cleanup, and clear network/error states.
6. Build and test each supported ABI on a real Android device before calling this embedded engine functional. Compare APK size and split-APK delivery options before shipping.

This is the preferred technical direction for the requested integrated player, but it does **not** provide a catalog, episode metadata, or voiceover choices by itself. Those must come from a separate permitted catalog/source provider. Playback is limited to user-provided or otherwise authorized sources.

### Option C — implement our own engine

This provides control but has the highest cost and maintenance risk. It requires torrent protocol support, peer discovery, piece prioritization, integrity verification, seek-aware buffering, retries, rate limits, cache management, and security hardening. Do not start from scratch until the embedded/standalone option has been evaluated.

## Phased implementation

1. Keep the current no-fake-data media UI and external ZONA handoff as a temporary state.
2. Add a provider-neutral engine interface and tests with a fake engine; no torrent downloads yet.
3. Add a user-configured TorrServer endpoint, validate it, and check the documented `GET /echo` health endpoint. Then test against an instance the developer controls before connecting playback.
4. Add playback only for user-provided or otherwise authorized torrent sources, with clear progress/error/cancel states and bounded cache.
5. Evaluate whether to bundle the engine only after Android packaging, license, privacy, and security reviews.
6. Integrate a real metadata provider only where documented API access or permitted data access is available. Never promise that TorrServer alone provides ZONA's catalog.

## Acceptance criteria

- No hard-coded provider API keys or undocumented endpoint assumptions.
- No fabricated titles, posters, ratings, voiceovers, or playback URLs.
- UI and tests work when no engine/catalog is configured.
- User can cancel playback, clear cache, and see cache usage.
- Network endpoints are validated; credentials and magnet URIs are not written to logs.
- Existing news/AI features remain independent from media engine failures.
