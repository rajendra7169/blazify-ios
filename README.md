# Blazify iOS — pipeline test

Minimal SwiftUI player that proves the no-Mac build/install pipeline works:

`Ubuntu → GitHub → Codemagic (unsigned .ipa) → SideStore → iPhone`

It plays one fixed public audio file and supports background playback + lock-screen
controls. Once this is confirmed on-device, the YouTube extractor backend and the
full Blazify design come next.

Bundle ID: `com.rajendra.blazifyplayer`
