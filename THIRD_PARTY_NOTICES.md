# Third-party notices

Brim is licensed under the [GNU General Public License v3.0](LICENSE). It has no package
dependencies and bundles no third-party code, fonts, sounds or images. This file credits ideas
and techniques it builds on, and the online services it can talk to.

## Techniques credited

| What | Where in Brim | Credit |
|---|---|---|
| Running a small helper inside `/usr/bin/perl` so macOS 15.4+ still answers MediaRemote requests | `Resources/MediaRemoteHelper/` | [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause). Brim's helper is a separate implementation. |
| Showing windows on the lock screen through window-server space delegation | `Sources/Brim/LockScreen/SkyLightBridge.swift` | [Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) (MIT). Brim's bridge is a separate implementation. |
| LocalSend v2 protocol | `Sources/Brim/Droplets/LocalSend/` | [localsend/protocol](https://github.com/localsend/protocol). Brim implements the published protocol; no LocalSend code is included. |

## Private macOS frameworks

Brim loads these Apple frameworks at runtime when a feature needs them, and turns the feature
off if they are missing. They are not bundled, may change with any macOS update, and are the
reason Brim cannot ship on the Mac App Store:

- **MediaRemote**: now-playing information and media keys
- **DisplayServices**: display brightness HUD
- **CoreBrightness**: keyboard backlight HUD
- **SkyLight**: lock-screen cards

## Online services

Nothing is sent anywhere unless the feature below is in use. Brim has no analytics, telemetry or
accounts.

| Service | Used for | What is sent |
|---|---|---|
| [LRCLIB](https://lrclib.net) | Synced lyrics | Song title, artist, album and length |
| [AMLL TTML DB](https://api.amll.dev) | Word-by-word lyrics | Song title |
| [Open-Meteo](https://open-meteo.com) | Weather widget | Approximate location. Weather data by Open-Meteo.com, licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| [0x0.st](https://0x0.st) or a URL you configure | Upload a screenshot (only when you choose Upload) | The image. 0x0.st is public and anonymous; anyone with the link can open it |
| YouTube Music artwork (`i.ytimg.com`) | Album art for the playing song | The artwork URL the player shows |

Lyrics are fetched on demand and are not stored in this repository. Web searches, translations
and chat apps that Brim offers as shortcuts (DuckDuckGo, Google Translate, WhatsApp Web, Telegram
Web, Discord) open in your browser only when you click them.

## Trademarks

Apple, Mac, macOS, AirPods, Dynamic Island, Liquid Glass, Apple Music and other Apple product
names are trademarks of Apple Inc. Spotify, YouTube Music, Zoom, Microsoft Teams, Google Meet,
Discord, WhatsApp, Claude, Codex, Maccy, Clipy, Raycast and Paste are trademarks of their
respective owners. Brim is an independent project, not affiliated with or endorsed by any of them.
