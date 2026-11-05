#!/usr/bin/env bash
set -euo pipefail
mkdir -p .qa-apk
if [[ "${FRESH_CANDIDATE:-false}" = true ]]; then
  source=$(git rev-parse HEAD)
elif [[ -f .qa-apk/source.txt ]]; then
  source=$(tr -d '\r\n' < .qa-apk/source.txt)
else
  source=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$APK_RUN" --jq .head_sha)
fi
[[ "$source" =~ ^[a-f0-9]{40}$ ]]
changes=$(git diff --name-only "$source" HEAD -- . ':!tool/qa' ':!tool/perf' ':!test_performance' ':!.github/workflows' ':!docs/testing')
test -z "$changes" || { echo 'Profile APK source differs from the current application'; exit 2; }
sudo apt-get update -qq
sudo apt-get install -y apksigner aapt
apksigner verify --print-certs .qa-apk/app-debug.apk > .qa-apk/debug-certificate.txt
apksigner verify --print-certs .qa-apk/app-profile.apk > .qa-apk/profile-certificate.txt
debug=$(sed -n 's/Signer #1 certificate SHA-256 digest: //p' .qa-apk/debug-certificate.txt)
profile=$(sed -n 's/Signer #1 certificate SHA-256 digest: //p' .qa-apk/profile-certificate.txt)
[[ "$debug" =~ ^[a-f0-9]{64}$ ]]
test "$debug" = "$profile"
aapt dump badging .qa-apk/app-profile.apk > .qa-apk/profile-package.txt
grep -q "package: name='com.vitalis.vitalis_app'" .qa-apk/profile-package.txt
sha256sum .qa-apk/app-debug.apk > .qa-apk/SHA256SUMS
sha256sum .qa-apk/app-profile.apk | awk '{print $1}' > .qa-apk/profile.sha256
printf '%s\n' "$source" > .qa-apk/source.txt
