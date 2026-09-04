<div align="center">

<img src="docs/assets/logo.png" alt="Blazify" width="120" />

# Blazify for iPhone 🔥

**A music player for iOS, built in SwiftUI.**

*Stream it. Feel it. Blaze it.*

**Download it now** — one click, straight from the newest release.

[![android](https://img.shields.io/badge/Download_for_Android-FFA726?style=for-the-badge&logoColor=1A0E00&logo=android)](https://github.com/rajendra7169/blazify/releases/latest/download/Blazify.apk) [![windows](https://img.shields.io/badge/Download_for_Windows-FFA726?style=for-the-badge&logoColor=1A0E00&logo=windows)](https://github.com/rajendra7169/blazify-desktop/releases/latest/download/Blazify-setup.exe) [![linux](https://img.shields.io/badge/Download_for_Linux-FFA726?style=for-the-badge&logoColor=1A0E00&logo=linux)](https://github.com/rajendra7169/blazify-desktop/releases/latest/download/Blazify.deb) [![iphone](https://img.shields.io/badge/Download_for_iPhone-FFA726?style=for-the-badge&logoColor=1A0E00&logo=apple)](https://github.com/rajendra7169/blazify-ios/releases/latest/download/Blazify.ipa)

**[blazify website](https://rajendra7169.github.io/blazify/)** · downloads and screenshots for every platform

[![License](https://img.shields.io/badge/license-GPL--3.0-FFA726.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-FFA726)
![UI](https://img.shields.io/badge/UI-SwiftUI-FFA726)
![Status](https://img.shields.io/badge/status-in%20development-FFA726)

</div>

---

## Overview

Blazify streams from a large online catalogue, plays the music already on your
phone, follows the words as they are sung, and lets you restyle most of the app
while you use it. No advertisements, no tracking, and no account required.

**It is early.** The first build is tagged and downloadable, but this is
`0.1.0` and it shows. See [Install](#install) for what sideloading involves.

---

## Blazify everywhere else

The same player, built natively for each place you use it. The buttons at
the top of this page download any of them directly — these are the repos, if
you want the source.

| Platform | Source |
|---|---|
| **Android**<br><sub>phones and tablets</sub> | [rajendra7169/blazify](https://github.com/rajendra7169/blazify) |
| **Windows**<br><sub>installer</sub> | [rajendra7169/blazify-desktop](https://github.com/rajendra7169/blazify-desktop) |
| **Linux**<br><sub>deb, AppImage or tar.gz</sub> | [rajendra7169/blazify-desktop](https://github.com/rajendra7169/blazify-desktop) |
| **iPhone**<br><sub>sideloaded</sub> | [rajendra7169/blazify-ios](https://github.com/rajendra7169/blazify-ios) **← you are here** |

Screenshots, install guides and everything else: **[blazify website](https://rajendra7169.github.io/blazify/)**

---

## Features

### 🎵 Playback

| Feature | What it does |
|---|---|
| **Streaming** | Search or browse songs, albums, artists and playlists |
| **Local music** | Import audio from Files and play it beside everything else |
| **Downloads** | Keep songs on the device for when there is no connection |
| **Queue** | Reorder, save as a playlist, or start a radio from anything |
| **Background audio** | Keeps playing with the screen off, with lock-screen controls |
| **Sleep timer** | Including an end-of-track option |

### 🎚️ Sound

| Feature | What it does |
|---|---|
| **Equalizer** | Multi-band, with its own DSP and presets |
| **Audio cache** | Songs held as you play them, so replays cost no data |
| **Stream sources** | Choose which clients are used to resolve audio |

### 📖 Lyrics

| Feature | What it does |
|---|---|
| **Synced lyrics** | Word-by-word highlighting, including TTML timing |
| **Romanization** | For singing along to a script you cannot read |
| **AI translation** | Optional, with your own API key. Nothing is bundled |
| **Lyrics cache** | Kept for offline reading |

### 🎨 Look & Feel

| Feature | What it does |
|---|---|
| **Player designs** | Vinyl turntable, cassette tape, ring, and more |
| **Colour from artwork** | The interface takes its colour from what is playing |
| **Live preview** | Change the look and watch it change as you pick |
| **Home widget** | A separate widget target |

### 👥 Library & extras

| Feature | What it does |
|---|---|
| **Listen Together** | Play in sync with friends |
| **Sign in with Google** | Optional. Brings your YouTube Music library and playlists |
| **Backup & restore** | Your whole library in one file |
| **Music recognition** | Name what is playing in the room |
| **last.fm** | Scrobble what you play, with your own credentials |
| **Listening stats** | What you actually played, and how much |
| **Siri intents** | App intents for voice control |

---

## Install

Blazify is not on the App Store, and cannot be. Apps that stream audio from
YouTube are removed from it.

Download **[Blazify.ipa](https://github.com/rajendra7169/blazify-ios/releases/latest/download/Blazify.ipa)**
from the releases page. It is unsigned, so you install it with
[SideStore](https://sidestore.io) or [AltStore](https://altstore.io).

Two things to know before planning around it:

- Sideloaded apps signed with a free Apple ID **expire after seven days** and
  must be resigned. SideStore and AltStore can do that in the background, but
  they have to be set up first.
- iOS 17.0 or newer is required.

### Building it yourself

The point of this project's setup is that **no Mac is needed**. The project is
generated with XcodeGen and built on Codemagic's macOS runners:

```
Linux or Windows  →  GitHub  →  Codemagic  →  unsigned .ipa  →  SideStore  →  iPhone
```

Everything the build needs is in [`codemagic.yaml`](codemagic.yaml) and
[`project.yml`](project.yml). Point a free Codemagic account at a fork of this
repository and it produces `BlazifyPlayer.ipa` as an artifact.

If you do have a Mac:

```bash
brew install xcodegen
xcodegen generate
open BlazifyPlayer.xcodeproj
```

---

## Tech

| | |
|---|---|
| **Language** | Swift |
| **UI** | SwiftUI |
| **Minimum** | iOS 17.0 |
| **Project** | Generated by XcodeGen from `project.yml`, so no `.xcodeproj` is committed |
| **CI** | Codemagic, building unsigned on macOS runners |
| **Bundle ID** | `com.rajendra.blazifyplayer` |

One deliberate oddity worth knowing about: the build rewrites `__LINKEDIT`
after `xcodebuild`. Without it the app is signed correctly by a third-party
tool and still refuses to launch, because dyld rejects the layout Xcode leaves
behind for an unsigned build. That fix is why this pipeline works at all.

---

## Disclaimer

This project is not affiliated with, funded, authorized, endorsed by, or in any
way associated with YouTube, Google LLC, Apple Inc., or any of their affiliates
and subsidiaries.

All trademarks, service marks, and intellectual property rights referenced in
this project belong to their respective owners.

---

## License

Released under the **[GNU General Public License v3.0](LICENSE)**.

Written from scratch in Swift. It shares its name, its look and its ideas with
the Android and desktop builds of Blazify, but none of their code.

<div align="center">

Made with ❤️ by **Rajendra Pandey** in Kathmandu, Nepal

[Website](https://www.rajendrapandey.info.np/) · [GitHub](https://github.com/rajendra7169) · [Instagram](https://www.instagram.com/raja.indra7169)

</div>
