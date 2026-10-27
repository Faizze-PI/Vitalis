# Observed build warnings

This register records specific observations, not a blanket waiver for warnings.
New warnings and failing tasks still require investigation.

## BW-001 — pinned Flutter Kotlin build tooling

- **Observed:** 28 October 2026, Windows Android host transfer gate.
- **Message:** `Unsupported Kotlin plugin version`; Gradle's `embedded-kotlin`
  and `kotlin-dsl` report Kotlin `2.0.21`, while the requested plugin is `2.2.20`.
- **Source:** the pinned Flutter 3.44.7 SDK's
  `packages/flutter_tools/gradle/build.gradle.kts` declares `kotlin-dsl` and
  `kotlin("jvm") version "2.2.20"`. This is upstream SDK build tooling, not a
  VITALIS Kotlin source change.
- **Owner:** VITALIS build maintainer; upstream component is Flutter's Gradle
  plugin with the pinned Gradle 8.14.6 distribution.
- **Disposition:** `OPEN_VERIFICATION`. The warning's origin is identified;
  Android transfer coverage, test compilation and lint are still running.
  This record does not establish compatibility or a passing host gate.
- **Action:** retain the complete build output and task outcomes, then review
  compatibility against the pinned toolchain. Do not edit the installed SDK,
  suppress warnings globally or upgrade dependencies merely to hide the message.
- **Review deadline:** 27 November 2026, or any Flutter/Gradle/Kotlin change,
  whichever occurs first.

Gradle task states such as `NO-SOURCE`, `UP-TO-DATE` and a skipped plugin
configuration-check task are not counts of skipped product test cases. Product
test totals and skips must come from their actual test-result reports.
