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
