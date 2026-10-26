# Android 1.0.1 preview provenance

Private development source checkpoint: `7285c5f`. This repository contains a source-only export; private phone evidence and development history are excluded.

Flutter 3.44.7 / Dart 3.12.2; JDK 21.0.9; NDK 28.2.13676358. Android arm64, minimum API 28, target API 35. Profile AOT build, debug-signed testing preview.

APK: `VITALIS-1.0.1-arm64-v8a.apk`

SHA-256: `2185644d0af5370cd15d0535a9650274df273577048b9c888152c9b6f777c619`

Signing certificate SHA-256: `071d5608eed3d00d36a573ab728409a040c85eaa3ec7bb972a0e9b7164420b1d`.

Model weights download separately. No production signing material is included.

## Windows portable preview

Windows development source: `d5800b39bce5266d84f7f5584fd6070ed79fe45b`. Its source-only export is pinned by the immutable `windows-v1.0.1` tag; the binary carries its development identity in BUILD_PROVENANCE.json. The existing v1.0.1 tag identifies the earlier Android source export. The two preview assets therefore have distinct source identities.

File: `VITALIS-1.0.1-windows-x64.zip`

SHA-256: `37adef8e70a106a771e3651a26f656b2d41dd848a5d441723b814a117359f032`

Unsigned x64 release-mode CPU testing preview; model weights are not included.
