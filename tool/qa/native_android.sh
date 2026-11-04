#!/usr/bin/env bash
set -euo pipefail
out=".qa-results/$QA_SUITE"
mkdir -p "$out"
test "$(uname -m)" = aarch64
sudo apt-get update -qq
sudo apt-get install -y adb aapt apksigner zipalign
if ! sudo modprobe binder_linux devices=binder,hwbinder,vndbinder; then
  sudo apt-get install -y "linux-modules-extra-$(uname -r)"
  sudo modprobe binder_linux devices=binder,hwbinder,vndbinder
fi
# Execution-only layout uses native distro tools, not x86 Android SDK binaries.
export ANDROID_HOME="$RUNNER_TEMP/android-native-tools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
mkdir -p "$ANDROID_HOME/platform-tools" "$ANDROID_HOME/build-tools/35.0.0/lib"
for binary in adb aapt aapt2 apksigner zipalign; do
  if command -v "$binary" >/dev/null; then
    ln -sf "$(command -v "$binary")" "$ANDROID_HOME/platform-tools/$binary"
    ln -sf "$(command -v "$binary")" "$ANDROID_HOME/build-tools/35.0.0/$binary"
  fi
done
if test -f /usr/share/java/apksigner.jar; then
  ln -sf /usr/share/java/apksigner.jar "$ANDROID_HOME/build-tools/35.0.0/lib/apksigner.jar"
fi
{ uname -a; dpkg-query -W adb aapt apksigner zipalign; java -version; } > "$out/native-host-tools.log" 2>&1
image=redroid/redroid@sha256:dc2024a999dd0acb1112a23cddc9537ec8cb60a0dbe5a87ce9fbd75a2f5e94d2
docker pull "$image"
docker run -d --name "$QA_ANDROID_CONTAINER" --label "com.vitalis.ci=$GITHUB_RUN_ID" --privileged --cpus=3 --memory=6g -p 127.0.0.1:5555:5555 "$image" androidboot.use_memfd=1 androidboot.redroid_gpu_mode=guest androidboot.redroid_width=720 androidboot.redroid_height=1280 ro.secure=1
for attempt in $(seq 1 120); do
  adb connect 127.0.0.1:5555 >/dev/null 2>&1 || true
  boot=$(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') || boot=''
  if test "$boot" = 1; then break; fi
  sleep 2
done
test "$boot" = 1
adb unroot
timeout 60 adb wait-for-device
test "$(adb shell id -u | tr -d '\r')" = 2000
test "$(adb shell getprop ro.product.cpu.abi | tr -d '\r')" = arm64-v8a
expected=$(awk '{print $1}' .qa-apk/SHA256SUMS)
test "$(sha256sum .qa-apk/app-debug.apk | awk '{print $1}')" = "$expected"
bash tool/qa/android.sh
