# VITALIS

<img src="docs/branding/app-icon.png" width="96" alt="VITALIS logo">

Local AI chat for Android and Windows. Download GGUF models from Hugging Face or import your own, then chat on your device.

[**Android APK**](https://github.com/Faizze-PI/Vitalis/releases/latest/download/VITALIS-1.0.1-arm64-v8a.apk) · [**Windows ZIP**](https://github.com/Faizze-PI/Vitalis/releases/latest/download/VITALIS-1.0.1-windows-x64.zip) · [Releases](https://github.com/Faizze-PI/Vitalis/releases) · [Report a bug](https://github.com/Faizze-PI/Vitalis/issues)

Android 9+ arm64 · Windows x64 preview · Apache-2.0

> **Preview builds:** Android uses debug signing; Windows is unsigned. Both have [known issues](docs/public/STATUS.md). Performance and release testing are still in progress.

## Features

- Run models on-device with llama.cpp.
- Browse public Hugging Face GGUF models or import local files.
- Choose a model and generation settings for each chat.
- Create personas and attach notes to conversations.
- Save chat history and export conversations to the clipboard.
- Switch between light and dark themes.

## Getting started

1. Download the Android APK or Windows ZIP from [Releases](https://github.com/Faizze-PI/Vitalis/releases/latest). On Windows, extract the complete ZIP and open `VITALIS.exe`.
2. Open **Model Library** and download a model, or import a GGUF file.
3. Choose **Use for this chat** to select an installed model.

Model weights download separately. Qwen3.5 0.8B Q4_K_M is the default option; larger models need more memory and may run slowly. Model licences apply separately.

If Android reports a signature mismatch when updating, keep your existing installation and data. Do not uninstall to work around it.

## Privacy

Inference runs locally. Model search and downloads connect to Hugging Face and its file hosts. Those requests do not include your conversations. See the [privacy notes](docs/public/PRIVACY.md).

## Development

Built with Flutter and Provider, with llama.cpp through Dart Native Assets. Android is available as a preview. Windows x64 is also available as a portable preview; Linux is deferred.

- [Build and test instructions](docs/public/BUILDING.md)
- [Known issues and test status](docs/public/STATUS.md)
- [Contributing](CONTRIBUTING.md)
- [Security reports](SECURITY.md)

## Licence

VITALIS uses [Apache-2.0](LICENSE). Third-party code keeps its own licences; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [NOTICE](NOTICE).
