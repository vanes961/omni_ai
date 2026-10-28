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

TorrServer is explicitly **not part of the product design**. Do not require a TorrServer process, server URL, external installation, health check, or TorrServer settings for playback. Existing legacy adapter/settings code must be removed from the active playback path in a controlled cleanup after references and tests are audited.

### Selected approach — embed libtorrent4j (standalone engine)

The first library candidate is [libtorrent4j](https://github.com/aldenml/libtorrent4j), whose Java API wraps the native libtorrent engine and whose project declares the MIT license. Keep it as a candidate until an Android build proves the selected artifacts work together; a dependency declaration alone is not a working player.

**Android compatibility constraint:** the repository currently sets `minSdk = 26`. The upstream changelog states that `2.0.5-22` supports Android API 24 and newer, while the current `2.1.0-39` line requires API 28 or newer. Therefore, do not blindly select the newest release: first validate `2.0.5-22` against the app's Kotlin/Gradle toolchain and all target ABIs. The pinned candidate is `2.0.5-22` (not `2.1.0-39`, because the latter requires API 28+). Maven coordinates are split by ABI and all must use the same version:

- Java API: `org.libtorrent4j:libtorrent4j:2.0.5-22`
- ARM 32-bit: `org.libtorrent4j:libtorrent4j-android-arm:2.0.5-22`
- ARM 64-bit: `org.libtorrent4j:libtorrent4j-android-arm64:2.0.5-22`
- x86: `org.libtorrent4j:libtorrent4j-android-x86:2.0.5-22`
- x86_64: `org.libtorrent4j:libtorrent4j-android-x86_64:2.0.5-22`

The feature branch now has a CI-only Gradle configuration and `verifyLibtorrent4jArtifacts` task that resolves the base artifact and all four ABI artifacts without adding them to the app runtime or APK. This is deliberately a packaging-neutral first check: a passing task proves Maven publication/coordinates and non-empty downloads only. It does **not** prove Kotlin API compilation, JNI loading, device runtime compatibility, ABI coverage in an APK, or playback. After this probe passes, the next stage is a controlled integration build with an explicit APK-size comparison and supported-ABI strategy.

See the [upstream changelog](https://github.com/aldenml/libtorrent4j/blob/master/changelog.txt), [Maven Central base artifact](https://central.sonatype.com/artifact/org.libtorrent4j/libtorrent4j), and [Maven Central Android ARM64 artifact](https://central.sonatype.com/artifact/org.libtorrent4j/libtorrent4j-android-arm64).

Required implementation slices, in order:

1. Add a native session owner with serialized start/stop, no blocking native shutdown on the UI thread, and a single shared session rather than one session per episode.
2. Add a Flutter platform channel for open/status/cancel/close. Validate magnet hashes before crossing the channel; never log the complete magnet URI.
3. Resolve metadata and expose the real file list. Select an episode only on an unambiguous season/episode match; otherwise return the candidate list for an explicit in-app choice.
4. Prioritize the selected file and implement a loopback HTTP server with correct byte-range responses so `video_player` can seek without copying the entire video first.
5. Add buffer/readiness timeouts, cancellation, process/activity lifecycle handling, bounded cache and cleanup, and clear network/error states.
6. Build and test each supported ABI on a real Android device before calling this embedded engine functional. Compare APK size and split-APK delivery options before shipping.

This is the preferred technical direction for the requested integrated player, but it does **not** provide a catalog, episode metadata, or voiceover choices by itself. Those must come from a separate permitted catalog/source provider. Playback is limited to user-provided or otherwise authorized sources.


## Phased implementation

1. Keep the current no-fake-data media UI; do not invent a catalog or playback URL.
2. Add a provider-neutral engine interface and tests with a fake engine before starting native downloads.
3. Integrate libtorrent4j as an Android runtime dependency only after the artifact/ABI probe passes, then compile a minimal Kotlin session wrapper.
4. Add the Flutter platform bridge for magnet/torrent input, metadata, file selection, progress, cancellation, and close. Validate inputs and never log full magnet URIs.
5. Add a bounded loopback HTTP byte-range server for the selected file and verify seek-aware playback on real devices before advertising torrent playback as functional.
6. Integrate catalog/source providers only where documented API access or permitted data access is available. Catalog discovery and actual torrent availability are separate responsibilities.

## Acceptance criteria

- No hard-coded provider API keys or undocumented endpoint assumptions.
- No fabricated titles, posters, ratings, voiceovers, or playback URLs.
- UI and tests work when no engine/catalog is configured.
- User can cancel playback, clear cache, and see cache usage.
- Network endpoints are validated; credentials and magnet URIs are not written to logs.
- Existing news/AI features remain independent from media engine failures.
