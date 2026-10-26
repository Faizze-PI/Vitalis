# Building VITALIS

Run these commands from the repository root.

## Build prerequisites

The authority is [`tool/toolchain_policy.json`](../../tool/toolchain_policy.json):

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

## Checks

Use the same configured environment. Before the full test suite, restore the inactive CI example locally as described below so CI-policy checks can read it:

```powershell
./tool/run_gate.ps1 analyze
./tool/run_gate.ps1 test
```

The POSIX equivalents use `./tool/run_gate.sh`. Model-backed native tests additionally require a hash-verified `VITALIS_TEST_MODEL` fixture; see [the product native gate](../../third_party/llm_llamacpp/test/vitalis_text_runtime_gate_test.dart). Generic upstream tests are not equivalent to the VITALIS acceptance gate.

CI is included as an [inactive example](ci-workflow.example.yml). The current publication login does not have GitHub's `workflow` permission, so no active Actions workflow is uploaded. No hosted CI success is claimed.

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

