# Third-party notices

Brim is licensed under the [GNU General Public License v3.0](LICENSE). It bundles the
[Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/tree/2.10.1) update framework
under its MIT license and the included dependency licenses reproduced below. This file also
credits techniques it builds on and the online services it can talk to.

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
| GitHub Releases (`github.com`, `objects.githubusercontent.com`) | Signed application updates | App version and standard HTTPS request metadata; no system profile is sent |
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

## Sparkle license and bundled dependency notices

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

```
