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

### Rejected approach — TorrServer

TorrServer is explicitly **not part of the product design**. Do not require a TorrServer process, server URL, external installation, health check, or TorrServer settings for playback. Legacy TorrServer adapters/settings have been removed from the active playback path.

### Selected approach — embedded libtorrent4j

The app integrates [libtorrent4j](https://github.com/aldenml/libtorrent4j), whose Java API wraps the native libtorrent engine and whose project declares the MIT license. A dependency declaration alone is not considered a working player; compilation, packaging, and real-device playback are separate acceptance gates.

The app currently pins version `2.0.5-22`, compatible with the repository's `minSdk = 26` constraint according to the upstream changelog. All four Android ABI artifacts use the same version:

- Java API: `org.libtorrent4j:libtorrent4j:2.0.5-22`
- ARM 32-bit: `org.libtorrent4j:libtorrent4j-android-arm:2.0.5-22`
- ARM 64-bit: `org.libtorrent4j:libtorrent4j-android-arm64:2.0.5-22`
- x86: `org.libtorrent4j:libtorrent4j-android-x86:2.0.5-22`
- x86_64: `org.libtorrent4j:libtorrent4j-android-x86_64:2.0.5-22`

CI includes a `verifyLibtorrent4jArtifacts` task to resolve the pinned artifacts and check ABI coverage. The native Android bridge is integrated in the app runtime, not just a CI-only dependency probe.

## Current implementation

The feature branch contains these components:

1. **Native session bridge** (`TorrentSessionBridge.kt`): owns a shared `SessionManager`, starts DHT, validates magnet info hashes, stores data under app-private storage, reports status, exposes torrent metadata/file lists, changes file priorities, and stops a torrent.
2. **Flutter method channel** (`omni_ai/torrent_engine`): exposes magnet start, status, file listing/selection, playback URL creation, and stop operations to Dart.
3. **Loopback Range server** (`TorrentRangeServer.kt`): serves the selected file on `127.0.0.1` with a tokenized URL, supports `HEAD` and HTTP byte ranges, and waits for requested torrent pieces before serving bytes to avoid reading sparse/preallocated file regions as valid video data.
4. **Player integration**: accepts a magnet URI, waits for metadata, filters candidate video files, prompts the user when multiple video files are present, selects the chosen file, and passes the local URL to the existing playback path. If torrent preparation fails, the player can continue to its configured fallback sources.

This describes implemented code, not a claim that streaming has been proven on every device. CI can validate source analysis, tests, Kotlin compilation, dependency resolution and APK packaging. It cannot prove tracker/DHT reachability, JNI loading on a particular phone, sustained buffering, seeking behavior, audio/subtitle selection, or lifecycle reliability.

## Remaining work and acceptance

1. Validate a real magnet on a physical Android device: metadata arrival, file list, selected-file playback, and cleanup after stopping.
2. Verify byte-range behavior during actual playback, including `HEAD`, initial `GET`, `206 Partial Content`, invalid ranges, seeking forward/backward, slow peers, and unavailable pieces.
3. Test cancellation, activity teardown, repeated start/stop, and switching between episodes; confirm no leaked sockets or background sessions.
4. Improve user-visible states and bounded cache management after runtime behavior is verified.
5. Compare APK size and consider ABI split delivery before shipping. The bundled native libraries increase APK size.
6. Integrate catalog/source providers only where documented API access or permitted data access is available. Catalog discovery and actual torrent availability are separate responsibilities.

## Constraints

- No hard-coded provider API keys or undocumented endpoint assumptions.
- No fabricated titles, posters, ratings, voiceovers, or playback URLs.
- UI and tests must work when no engine/catalog is configured.
- Users should be able to cancel playback, clear cache, and see cache usage.
- Validate network endpoints; do not write credentials or full magnet URIs to logs.
- News and AI features must remain independent from media-engine failures.
- Playback is limited to user-provided or otherwise authorized sources.
