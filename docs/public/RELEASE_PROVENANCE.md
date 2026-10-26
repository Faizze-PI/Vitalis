# Android 1.0.1 preview provenance

Private development source checkpoint: `7285c5f`. This repository contains a source-only export; private phone evidence and development history are excluded.

Flutter 3.44.7 / Dart 3.12.2; JDK 21.0.9; NDK 28.2.13676358. Android arm64, minimum API 28, target API 35. Profile AOT build, debug-signed testing preview.

APK: `VITALIS-1.0.1-arm64-v8a.apk`

SHA-256: `2185644d0af5370cd15d0535a9650274df273577048b9c888152c9b6f777c619`

Signing certificate SHA-256: `071d5608eed3d00d36a573ab728409a040c85eaa3ec7bb972a0e9b7164420b1d`.

Model weights download separately. No production signing material is included.

## Windows portable preview

Windows development source: `81de637ef70855039e6273e4cad67df5081d333d`. Its source-only export is in the subsequent Windows commit on this repository's main branch; the binary carries its development identity in BUILD_PROVENANCE.json. The existing v1.0.1 tag identifies the earlier Android source export. The two preview assets therefore have distinct source identities.

File: `VITALIS-1.0.1-windows-x64.zip`

SHA-256: `881b0a4147c57473ec62e0c8248e53fc7cbe0e2c298f2ddb849c1210736b4a9d`

Unsigned x64 release-mode CPU testing preview; model weights are not included.
