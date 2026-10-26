#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_root=${VITALIS_FLUTTER_SDK:-"$repo_root/.fvm/flutter_sdk"}
dart="$flutter_root/bin/cache/dart-sdk/bin/dart"
if [ -z "${VITALIS_GENERATION_TOKEN:-}" ]; then
  exec "$dart" "$repo_root/tool/generation_lock.dart" -- sh "$0" "$@"
fi
"$dart" "$repo_root/tool/generation_lock.dart" --verify

"$repo_root/tool/run_gate.sh" build apk --release --target-platform android-arm64
export GRADLE_USER_HOME="${VITALIS_GRADLE_CACHE:-$repo_root/.gate-cache/gradle}"
export PUB_CACHE="${VITALIS_PUB_CACHE:-$repo_root/.gate-cache/pub}"
registrant="$repo_root/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
if grep -q integration_test "$registrant"; then
  echo 'Release registrant contains the development-only integration_test plugin.' >&2
  exit 1
fi

(cd "$repo_root/android" && ./gradlew lintRelease)
"$repo_root/tool/run_gate.sh" build appbundle --release --target-platform android-arm64

apk="$repo_root/build/app/outputs/flutter-apk/app-release.apk"
aab="$repo_root/build/app/outputs/bundle/release/app-release.aab"
test -f "$apk"
test -f "$aab"

entries=$(unzip -Z1 "$apk")
abis=$(printf '%s\n' "$entries" | sed -n 's#^lib/\([^/]*\)/[^/]*\.so$#\1#p' | sort -u)
test "$abis" = 'arm64-v8a'
for library in libllama.so libggml.so libggml-base.so libggml-cpu.so; do
  if ! printf '%s\n' "$entries" | grep -qx "lib/arm64-v8a/$library"; then
    echo "Missing required release native library: $library" >&2
    exit 1
  fi
done
if { unzip -Z1 "$apk"; unzip -Z1 "$aab"; } | grep -Eiq '(^|/)([^/]+\.gguf|[^/]+\.(jks|keystore)|key\.properties)$'; then
  echo 'Release artifact contains a prohibited payload.' >&2
  exit 1
fi

verifier_classes="$repo_root/build/tool/unsigned-artifacts"
mkdir -p "$verifier_classes"
"$JAVA_HOME/bin/javac" -d "$verifier_classes" "$repo_root/tool/VerifyUnsignedArtifacts.java" "$repo_root/tool/VerifyUnsignedArtifactsTest.java" "$repo_root/tool/VerifyAndroidNativeInventory.java" "$repo_root/tool/VerifyAndroidNativeInventoryTest.java"
"$JAVA_HOME/bin/java" -cp "$verifier_classes" VerifyUnsignedArtifactsTest
"$JAVA_HOME/bin/java" -cp "$verifier_classes" VerifyUnsignedArtifacts "$apk" "$aab"
"$JAVA_HOME/bin/java" -cp "$verifier_classes" VerifyAndroidNativeInventoryTest
"$JAVA_HOME/bin/java" -cp "$verifier_classes" VerifyAndroidNativeInventory "$apk" "$aab"
"$dart" "$repo_root/tool/verify_native_asset_manifest.dart" "$apk" apk
"$dart" "$repo_root/tool/verify_native_asset_manifest.dart" "$aab" aab
"$JAVA_HOME/bin/javac" -d "$verifier_classes" "$repo_root/tool/VerifyFlutterNotices.java" "$repo_root/tool/VerifyFlutterNoticesTest.java"
"$JAVA_HOME/bin/java" -cp "$verifier_classes" VerifyFlutterNoticesTest
"$dart" "$repo_root/tool/verify_flutter_notices.dart" "$apk" "$aab"

sha256sum "$apk" "$aab"
