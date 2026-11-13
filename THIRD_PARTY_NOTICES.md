# Third-party software

Relay is an independent implementation of a phone mirroring dashboard. It does not include Vysor source code, artwork, logos, or proprietary protocols, and is not affiliated with Vysor.

The public Git repository contains Relay's source. Build scripts download the [official scrcpy 5.0.1 release archives](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1) directly and verify their pinned SHA-256 checksums. The locally built macOS app includes the runtime and its upstream LICENSE in `Contents/Resources/runtime`. Universal installers combine the upstream Apple silicon and Intel slices with Apple's lipo tool and sign the files locally ad hoc.

Relay also loads its own `libRelayToolbar.dylib` companion into that local viewer to add native titlebar controls. This is Relay code, not an upstream scrcpy feature. The companion uses SDL 3’s published keyboard-event ABI; the official viewer executable is not patched.

- **scrcpy 5.0.1** — Copyright Genymobile and contributors. Apache License 2.0. [Source and license](https://github.com/Genymobile/scrcpy/tree/v5.0.1)
- **Android Debug Bridge 37.0.1** — Android Open Source Project. The copy in the macOS archive comes from Google's Android SDK Platform-Tools. [ADB source](https://android.googlesource.com/platform/packages/modules/adb/) and [Google Platform-Tools distribution](https://developer.android.com/tools/releases/platform-tools)
- **SDL 3.4.18** — zlib License. [Source and license](https://github.com/libsdl-org/SDL/tree/release-3.4.18)
- **FFmpeg 9.0.2** — statically linked by scrcpy’s release build. [Source archive](https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz), [licensing](https://ffmpeg.org/legal.html), and [scrcpy build flags](https://github.com/Genymobile/scrcpy/blob/v5.0.1/app/deps/ffmpeg.sh)
- **libusb 1.0.30** — LGPL 2.1 or later. [Source and license](https://github.com/libusb/libusb/tree/v1.0.30)
- **dav1d 1.5.4** — BSD 2-Clause License. [Source archive](https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/dav1d-1.5.4.tar.xz)

The upstream [macOS build recipe](https://github.com/Genymobile/scrcpy/blob/v5.0.1/release/build_macos.sh) and [dependency recipes](https://github.com/Genymobile/scrcpy/tree/v5.0.1/app/deps) describe how to rebuild and relink the viewer against these sources.

Apple’s iPhone Mirroring is a separate system application, owned by Apple. Relay launches it using its registered application identifier. No Apple application is redistributed in this project.
