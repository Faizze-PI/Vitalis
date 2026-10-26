#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_root=${VITALIS_FLUTTER_SDK:-"$repository_root/.fvm/flutter_sdk"}
flutter="$flutter_root/bin/flutter"
dart="$flutter_root/bin/cache/dart-sdk/bin/dart"
if [ -z "${VITALIS_GENERATION_TOKEN:-}" ]; then
  exec "$dart" "$repository_root/tool/generation_lock.dart" -- sh "$0" "$@"
fi
"$dart" "$repository_root/tool/generation_lock.dart" --verify

if [ ! -x "$flutter" ]; then
  echo 'Flutter is missing. Set VITALIS_FLUTTER_SDK or create .fvm/flutter_sdk.' >&2
  exit 2
fi
if [ -z "${JAVA_HOME:-}" ]; then
  echo 'JAVA_HOME must select JDK 21.0.9.' >&2
  exit 2
fi

"$flutter_root/bin/cache/dart-sdk/bin/dart" "$repository_root/tool/verify_toolchain_policy.dart"
versions=$("$flutter" --version --machine)
printf '%s' "$versions" | "$flutter_root/bin/cache/dart-sdk/bin/dart" \
  "$repository_root/tool/validate_flutter_version.dart" "$repository_root/tool/toolchain_policy.json"
jdk_version=$("$flutter_root/bin/cache/dart-sdk/bin/dart" \
  "$repository_root/tool/verify_toolchain_policy.dart" --value jdk)
"$JAVA_HOME/bin/java" -version 2>&1 | head -n 1 | grep -Fq "version \"$jdk_version\"" || {
  echo "VITALIS requires JDK $jdk_version." >&2
  exit 2
}

selected_pub="${VITALIS_PUB_CACHE:-$repository_root/.gate-cache/pub}"
selected_gradle="${VITALIS_GRADLE_CACHE:-$repository_root/.gate-cache/gradle}"
if ! "$dart" "$repository_root/tool/verify_gate_environment.dart" --same-directory "${PUB_CACHE:-$selected_pub}" "$selected_pub" ||
   ! "$dart" "$repository_root/tool/verify_gate_environment.dart" --same-directory "${GRADLE_USER_HOME:-$selected_gradle}" "$selected_gradle"; then
  echo 'Existing cache configuration conflicts with the selected workspace caches.' >&2
  exit 2
fi
export PUB_CACHE="$selected_pub"
export GRADLE_USER_HOME="$selected_gradle"
"$dart" "$repository_root/tool/verify_gate_environment.dart"
configuration=$("$flutter" config --machine)
printf '%s' "$configuration" | "$dart" "$repository_root/tool/verify_flutter_selection.dart"
mkdir -p "$PUB_CACHE" "$GRADLE_USER_HOME"

if [ "$#" -eq 0 ]; then
  echo 'Pass a Flutter command, for example: tool/run_gate.sh analyze --fatal-warnings' >&2
  exit 2
fi
if [ "$1" = clean ]; then
  "$flutter" "$@"
  exec "$dart" "$repository_root/tool/verify_clean_outputs.dart" "$repository_root"
fi
exec "$flutter" "$@"
