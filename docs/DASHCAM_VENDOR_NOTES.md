# Dashcam vendor capture notes (Nice DVR / Novatek-style HTTP)

`NiceDVRWiFiService` discovers clips by:

1. `GET http://<cam>/?custom=1&cmd=3015` (Novatek-style file list).
2. `GET http://<cam>/` and parsing `href="...mov|mp4"`.

## How to contribute observed behavior

When a camera does not list files:

1. Connect to the camera Wi‑Fi (same as the Nice DVR app).
2. In Safari, open `http://192.168.1.254` (or your gateway IP).
3. Save a **redacted** sample of HTML or CGI response (remove passwords, SSIDs if embedded).
4. Add a fixture under `Tests/KAutomobileTrackerTests/Fixtures/` and a unit test for `DashcamHTMLParser`, **or** open an issue with the sample attached.

Community background (not authoritative for all SKUs): [DashCamTalk — Reverse engineering, Web API, Live feed](https://dashcamtalk.com/forum/threads/reverse-engineering-web-api-live-feed-etc.21057/).

## Protocol seam

`NiceDVRWiFiService` conforms to `DashcamWiFiConnector` in [ServiceProtocols.swift](../Sources/KAutomobileTrackerCore/Protocols/ServiceProtocols.swift). Add another `DashcamWiFiListing` implementation for a different vendor when the same HTTP list/download pattern applies.
