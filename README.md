# Relay for Mac

Relay mirrors and controls Android phones from a native macOS app. Connect over USB or Wi-Fi, use your Mac’s keyboard and mouse, copy screenshots, and record the screen. Relay uses the official [scrcpy](https://github.com/Genymobile/scrcpy) runtime and adds its own SwiftUI dashboard and Cocoa viewer toolbar.

## Build and install

You need **macOS 14 or later**, **Swift 6 or later** from Xcode or the Xcode Command Line Tools, and **Python 3**. The first build downloads the official scrcpy archive for your Mac and verifies its SHA-256 checksum. The app bundles scrcpy and ADB, so you can run it on another Mac without the build tools.

```sh
git clone https://github.com/iawaisJavaid/relay-mac.git
cd relay-mac
./scripts/build-app.sh
open dist/Relay.app
```

The local build targets your Mac’s architecture. For a drag-to-Applications installer for both **Apple silicon and Intel**, run `./scripts/build-dmg.sh`. The disk image and its SHA-256 checksum appear in `dist/`. Open the image and drag Relay into Applications. Quit an existing copy of Relay before replacing it.

These builds use ad hoc signing. For a build you trust, follow [Apple’s app approval instructions](https://support.apple.com/en-us/102445) if macOS blocks the first launch. GitHub hosts the source. The build scripts fetch the upstream runtime separately.

## Connect an Android phone

1. Enable **Developer options** on your phone, then enable **USB debugging**. On many phones, tapping **Build number** seven times enables Developer options.
2. Connect with a USB data cable. Unlock the phone and approve the debugging prompt for your Mac.
3. In Relay, click **Mirror**. Use the viewer’s title bar to take a screenshot, start a recording, toggle audio, enter fullscreen, or open settings.

To go wireless, keep both devices on the same trusted Wi-Fi network. Start with the authorized USB connection and click **Connect via Wi-Fi** in Relay or **Wireless Mode** in the viewer’s gear menu. Relay discovers the phone’s address, reuses an authorized connection when available, and verifies the phone’s identity before switching. Unplug USB after Relay confirms the connection. If Relay enabled legacy ADB over TCP, it will try to restore USB-only debugging when you disconnect or quit.

Standard mirroring supports Android 5.0+ and audio requires Android 11+. Quality settings set limits for resolution, bitrate, and frame rate. The actual result depends on the phone and connection. [scrcpy device requirements](https://github.com/Genymobile/scrcpy/tree/v5.0.1#prerequisites)

| Viewer control | Action |
| --- | --- |
| Camera or **⌘⇧S** | Save a PNG, copy the image, and show a preview with a Save As action |
| Video camera or **⌘⇧R** | Start or stop an MP4 recording. Relay copies the file URL when the recording finishes |
| Headphones | Toggle phone audio. A muted speaker indicates audio is off or unavailable |
| Fullscreen or **⌘F** | Toggle fullscreen |
| Gear | Wireless Mode, Rotate Screen, Screen On/Off, Copy Logcat, and Settings |

Screenshots and recordings are saved under `~/Movies/Relay` by default. Change the folder in Relay’s dashboard **Settings**. Settings, recording, and audio changes restart the viewer. When you change settings during a recording, Relay finalizes the current clip and continues in a new one.

The **iPhone** card opens Apple’s iPhone Mirroring app. Its hardware, OS, account, and regional requirements apply. [Apple’s iPhone Mirroring requirements](https://support.apple.com/en-us/120421)

## Troubleshooting

- **Mac audio unavailable, or CoreAudio `AudioQueueStart` error.** Starting in Relay 1.2.2, a client audio startup failure triggers one retry without Mac audio playback. Video and controls still open if the connection is healthy. When recording, Relay still requests supported phone audio for the file. To restore playback, choose a working device under **System Settings → Sound → Output**, such as the MacBook speakers, then click the muted speaker in the viewer. A connected monitor or dock may provide a different audio output. The same workaround can help on earlier builds. [Apple’s sound output instructions](https://support.apple.com/guide/mac-help/mchlp2256/mac)
- **Phone is missing, offline, or unauthorized.** Unlock it, approve USB debugging, and try a different data cable or USB port. If Wi-Fi fails, reconnect USB and confirm both devices are on the same network. Some phone vendors require an additional USB debugging security setting for keyboard and mouse input.
- **Viewer is slow to start.** Check the phone for a prompt. If the mirror exits, open **Activity** for the underlying error. Remove any device identifiers or network addresses before sharing logs.

## Develop

```sh
./scripts/bootstrap-runtime.sh
./scripts/make-toolbar.sh
./scripts/swift.sh run
./scripts/swift.sh test
./scripts/verify-toolbar-bridge.sh
```

You can also open `Package.swift` in Xcode. `Sources/RelayCore` handles Android discovery, automatic Wi-Fi, command options and process execution. `Sources/RelayApp` contains the dashboard and viewer management. `Resources/Toolbar` contains the native toolbar. Tests use synthetic devices and cover argument handling, connection recovery, and viewer lifecycle behavior.

Relay’s original code and artwork are available under the [MIT License](LICENSE). The runtime has separate licenses and source locations. Relay is independent of Vysor and uses scrcpy with attribution. [Third-party notices](THIRD_PARTY_NOTICES.md)
