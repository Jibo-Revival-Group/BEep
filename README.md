# BEep

BEacon as an iPhone and iPad app. BEep finds Jibo on your Wi-Fi and opens BEacon, his web control panel.

- Finds every Jibo on the same Wi-Fi by itself, and remembers them.
- With one robot, it opens straight into BEacon.
- Add a robot by IP address if it isn't found (Jibo shows his IP in Settings › Wi-Fi).
- BEacon's pop-up questions show as iPhone alerts.
- Uploads use the iPhone photo and file pickers.
- Downloads (like Jibo's photos) open the share sheet, so you can save them to Photos or Files.
- Pull down to reload.

## Install

BEep is installed with AltStore or SideStore.

1. Download `BEep.ipa` from the latest release.
2. In AltStore or SideStore, open My Apps, tap +, and choose `BEep.ipa`.
3. When BEep asks to find devices on your local network, tap Allow.

Your phone must be on the same Wi-Fi as Jibo, and Jibo needs BEam with BEacon.

## Build

Every push builds `BEep.ipa` on GitHub's Macs (see `.github/workflows/build.yml`). Pushing a `v*` tag publishes a release.

On a Mac: `brew install xcodegen && xcodegen`, then open `BEep.xcodeproj`.
