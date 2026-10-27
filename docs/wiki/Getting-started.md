# Getting started

Use the assets attached to the [latest release](https://github.com/Faizze-PI/Vitalis/releases/latest), not GitHub's automatically generated source archives.

## Android

Download `VITALIS-1.0.1-arm64-v8a.apk`. The preview targets Android 9 or later on arm64 hardware and uses development signing. When upgrading, preserve the existing installation. If Android reports a certificate mismatch, stop; uninstalling would remove app data.

## Windows

Download `VITALIS-1.0.1-windows-x64.zip`, extract the entire archive, and open `VITALIS.exe`. Keep the accompanying files together. The unsigned preview has been exercised on Windows 11; cross-machine qualification remains open. Java is not required to run it.

## First conversation

Open Model Library, download the default model or import a compatible GGUF, then choose **Use for this chat**. Models are separate downloads; the app package does not include weights. Model load time depends on hardware and model size.

SHA-256 checksums accompany the release. They identify the published files; they do not replace code signing or establish production readiness.

For failures, record the app version, platform and exact action. Use disposable content in screenshots and [report a bug](https://github.com/Faizze-PI/Vitalis/issues/new/choose). Never attach a personal database or unredacted log.
