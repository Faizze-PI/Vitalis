#!/usr/bin/env bash
set -euo pipefail
mkdir -p ".qa-results/$QA_SUITE"
adb shell getprop > ".qa-results/$QA_SUITE/device-properties.txt"
abis=$(adb shell getprop ro.product.cpu.abilist | tr -d '\r')
if [[ "$abis" != *arm64-v8a* ]]; then
  echo "Selected emulator does not support the unchanged arm64 APK: $abis" >&2
  exit 2
fi
# This is a disposable hosted emulator. No personal handset or user data is used.
adb install -r .qa-apk/app-debug.apk
adb shell am start -W -n com.vitalis.vitalis_app/.MainActivity
appium --address 127.0.0.1 --port 4723 > ".qa-results/$QA_SUITE/appium.log" 2>&1 &
appium_pid=$!
trap 'kill "$appium_pid" 2>/dev/null || true' EXIT
python - <<'PY'
import time,urllib.request
for attempt in range(60):
    try:
        with urllib.request.urlopen('http://127.0.0.1:4723/status',timeout=2) as r:
            if r.status==200: break
    except OSError: time.sleep(1)
else: raise SystemExit('Appium server did not become ready')
PY
if [[ "${QA_NAVIGATION_SMOKE:-0}" = 1 ]]; then
  python tool/qa/navigation_smoke.py
else
  python tool/qa/run.py
fi
