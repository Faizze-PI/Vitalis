# VITALIS

An Android app for on-device AI conversations, reusable personas, attached notes, and local GGUF models.

**Development preview.** The source is available for development and review. Android release qualification is still in progress; this is not a production-ready or fully ratified release.

## Download for Android

**[Download the Android APK (testing preview, about 94 MB)](https://github.com/Faizze-PI/Vitalis/releases/download/preview-2026-10-26/VITALIS-1.0.0-preview-20261026-android-arm64.apk)**

Requires Android 9 or later and an arm64 device. Models download separately inside the app. This is a debug-signed testing build with known issues, not a production release. See the [release notes and checksum](https://github.com/Faizze-PI/Vitalis/releases/tag/preview-2026-10-26). If an update reports a signature mismatch, preserve your installation and data; do not uninstall as a workaround.

## Features

- Local CPU inference using a pinned llama.cpp backend through Dart Native Assets.
- Chat history, per-chat model settings, personas, persistent note attachments, and conversation export to the clipboard.
- Light and dark themes.
- Public Hugging Face GGUF search, model details, downloads, local import, and installed-model selection.
- Native cancellation and device-safety monitoring.

Inference runs on the device. Model browsing and downloads use the network; Hugging Face and its download hosts receive search/model requests and ordinary connection information. Conversation content is not included in those model-library requests. See [Privacy](docs/public/PRIVACY.md).

## Platform and status

| Item | Current boundary |
|---|---|
| App target | Android, `arm64-v8a` |
| Minimum Android API | 28; complete support-floor qualification remains open |
| Build SDK / target SDK | 36 / 35 |
| Default inference backend | CPU |
| Vulkan | Experimental, not release-qualified |
| Windows / Linux app runners | Deferred |
| Physical 16-KB page validation | Not established |

See [Validation status and known issues](docs/public/STATUS.md). Model answers can be inaccurate; a completed response does not establish instruction-following accuracy or performance acceptance.

## Build prerequisites

The authority is [`tool/toolchain_policy.json`](tool/toolchain_policy.json):

- Flutter **3.44.7**, Dart **3.12.2**.
- JDK **21.0.9**; Java bytecode target 17.
- Android SDK platform **36**, NDK **28.2.13676358**.
- Gradle **8.14.6**, supplied by the checked-in wrapper.

Use the gate launchers rather than an arbitrary system Flutter or Java installation. They check the toolchain and serialize generation in a checkout. Dependency and native-source lockfiles must remain intact.

### Windows PowerShell

From the repository root, replace the example SDK locations with your own:

```powershell
$env:VITALIS_FLUTTER_SDK = 'C:\SDKs\flutter-3.44.7'
$env:JAVA_HOME = 'C:\SDKs\jdk-21.0.9'
$env:ANDROID_HOME = 'C:\SDKs\Android'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PUB_CACHE = Join-Path $PWD '.gate-cache/pub'
$env:GRADLE_USER_HOME = Join-Path $PWD '.gate-cache/gradle'

./tool/run_gate.ps1 pub get --enforce-lockfile
./tool/run_gate.ps1 build apk --debug --target-platform android-arm64
```

### POSIX shell

```sh
export VITALIS_FLUTTER_SDK=/path/to/flutter-3.44.7
export JAVA_HOME=/path/to/jdk-21.0.9
export ANDROID_HOME=/path/to/android-sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PUB_CACHE="$PWD/.gate-cache/pub"
export GRADLE_USER_HOME="$PWD/.gate-cache/gradle"

./tool/run_gate.sh pub get --enforce-lockfile
./tool/run_gate.sh build apk --debug --target-platform android-arm64
```

The native build downloads hash-locked source archives. A first build therefore needs Internet access and can take longer. Do not obtain replacement native binaries from arbitrary download sites. Debug builds use development signing; production signing is outside this preview.

## Models

Qwen3.5 0.8B Q4_K_M is the configured default download. Its immutable revision and publisher hash are defined in [`BundledModelManifest`](lib/models/bundled_model_manifest.dart). Model weights are **not** committed to this repository.

Open **Model Library** to browse public models or import a local GGUF. After installation, choose **Use for this chat** explicitly. Device memory, supported templates and architecture affect compatibility. Larger models can be slow or exceed device resources; a download is not a guarantee of good output quality.

Each model's own licence applies to its weights. This repository does not grant rights to third-party model weights.

## Checks

Use the same configured environment. Before the full test suite, restore the inactive CI example locally as described below so CI-policy checks can read it:

```powershell
./tool/run_gate.ps1 analyze
./tool/run_gate.ps1 test
```

The POSIX equivalents use `./tool/run_gate.sh`. Model-backed native tests additionally require a hash-verified `VITALIS_TEST_MODEL` fixture; see [the product native gate](third_party/llm_llamacpp/test/vitalis_text_runtime_gate_test.dart). Generic upstream tests are not equivalent to the VITALIS acceptance gate.

CI is included as an [inactive example](docs/public/ci-workflow.example.yml). The current publication login does not have GitHub's `workflow` permission, so no active Actions workflow is uploaded. No hosted CI success is claimed.

For local CI-policy checks, first create `.github/workflows/ci.yml` from that example:

```powershell
New-Item -ItemType Directory -Force .github/workflows | Out-Null
Copy-Item docs/public/ci-workflow.example.yml .github/workflows/ci.yml
```

Or, in a POSIX shell:

```sh
mkdir -p .github/workflows
cp docs/public/ci-workflow.example.yml .github/workflows/ci.yml
```

The active workflow path is ignored in this preview. When ready to enable GitHub Actions, authorize workflow uploads and remove that single ignore entry before committing the active workflow. The initial source import does not run another test matrix.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Please report reproducible issues with redacted diagnostics, never credentials, personal chats, or full private device dumps.

## Licence

Original VITALIS application code is licensed under [Apache-2.0](LICENSE). Separately licensed third-party code retains its own terms and attribution; see [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and the vendored licence files.
