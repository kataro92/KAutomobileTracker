# RTSP live preview (research spike)

Many Wi‑Fi dashcams expose **RTSP** URLs for live view (e.g. `rtsp://192.168.1.254/…`). Nice DVR and similar apps use this for preview while using **HTTP** for file listing and download.

## Current product scope

KAutomobileTracker **analyzes files** (`AVAsset` / `AVAssetReader`) after download or local import. RTSP is **not** implemented.

## Possible directions

1. **`AVPlayer`** with `AVPlayerItem(url: rtspURL)` — simplest experiment; export to file may require `AVAssetExportSession` if the stream is exposed as a compatible asset (vendor-dependent).
2. **Record to temp file** while user drives, then run the existing analysis pipeline (complexity: duration, disk, interruption).
3. **Third-party** decoders (e.g. FFmpeg) — licensing and bundling cost on macOS.

Recommendation: keep file-based analysis solid; prototype RTSP in a **branch** with one known camera URL before committing to UX.

Reference thread (Novatek-oriented): [DashCamTalk — Reverse engineering, Web API, Live feed](https://dashcamtalk.com/forum/threads/reverse-engineering-web-api-live-feed-etc.21057/).
