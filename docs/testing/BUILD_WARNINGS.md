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
- **Disposition:** `TRACKED_UPSTREAM_TOOLING`. Android compilation, 155 JVM
  tests, the 18-source transfer coverage gate and debug lint completed
  successfully with this warning present. This is scoped host evidence, not
  cross-version or physical compatibility proof.
- **Action:** retain the complete build output and task outcomes, then review
  compatibility against the pinned toolchain. Do not edit the installed SDK,
  suppress warnings globally or upgrade dependencies merely to hide the message.
- **Review deadline:** 27 November 2026, or any Flutter/Gradle/Kotlin change,
  whichever occurs first.

## BW-002 — file-picker channel argument casts

- **Observed:** 28 October 2026, compiling `file_picker` 11.0.3 for Android.
- **Messages:** unchecked casts from `Any?` to `ArrayList<String>?` in
  `FilePickerPlugin.kt`, lines 148 and 170.
- **Source:** both upstream casts read the `allowedExtensions` method-channel
  argument before calling `getMimeTypes`. This observation is not evidence of
  an invalid file being accepted or an observed runtime crash.
- **Owner:** VITALIS dependency maintainer; upstream component is `file_picker`.
- **Disposition:** `OPEN_PHYSICAL_VERIFICATION`. The host gate completed with
  these warnings present. Import/document-picker behavior still needs
  its physical acceptance tests. No cached package sources or warning flags
  were modified.
- **Action:** review a compatible upstream correction with import/export and
  platform tests before changing the lockfile. Do not upgrade blindly or treat
  the warning as a passing functionality check.
- **Review deadline:** 27 November 2026, or a `file_picker`/channel API change,
  whichever occurs first.

## Completed host lint inventory

The 28 October run produced **33 warnings and three hints across 12 module
reports**. The application report contains zero errors and two warnings;
dependency baselines must not be presented as zero dependency errors. No new
baseline or warning suppression was added by this review.

The owner for BW-003 through BW-008 is the VITALIS build/dependency maintainer.
Review each before **27 November 2026**, any affected dependency/toolchain change,
or publication, whichever occurs first.

| ID | Observation and scope | Disposition and required evidence |
|---|---|---|
| BW-003 | App `OldTargetApi`, target 35 | Explicit pinned target policy. Revisit with target-version behavior tests; this is not a claim of store-policy compliance. |
| BW-004 | App `ChromeOsAbiSupport`, arm64 only | Intentional Android arm64 delivery boundary. x86/ChromeOS is not qualified by this preview. Do not add an untested ABI merely to silence lint. |
| BW-005 | Dependency `AndroidGradlePluginVersion`, `GradleDependency`, `NewerVersionAvailable`, `UseRequiresApi`, `ObsoleteSdkInt`, and `KtxExtensionAvailable` | Retained upstream advisories. Review compatible upgrades and API behavior individually; no bulk upgrade or runtime-safety conclusion follows from lint success. |
| BW-006 | Flutter `integration_test` declares three floating Android test selectors | The root applies `android/test-dependency-policy.gradle` to every project/configuration. The offline Gradle regression resolved deliberately floating root and plugin fixture dependencies to policy-pinned versions. Static lint still sees the upstream declarations. These are debug/test dependencies, not proof that they enter release output. |
| BW-007 | `shared_preferences_android` 2.4.23 baseline filters two `MemberExtensionConflict` errors; emits `LintBaseline` and `LintBaselineFixed` hints | Existing upstream baseline, unchanged. Conflicts concern `Set.contains` member/extension resolution in `SharedPreferencesPlugin.kt` and `StringListObjectInputStream.kt`. Preserve this limitation and review upstream behavior; do not report an error-free dependency audit. |
| BW-008 | Gradle structured problems: 15 Groovy property-assignment deprecations, one task-project access at execution time, two null attribute-key retrievals | `OPEN_ORIGIN_REVIEW`. Full structured diagnostics are retained; their precise owning plugins/scripts still need attribution before a Gradle upgrade. No claim of Gradle 9/10 compatibility. |

The host command was `:app:transferCoverageVerify
:app:compileDebugAndroidTestJavaWithJavac lintDebug`. It passed at checkpoint
`3f0736634c34ac828510aedb754c82708400bbc3`, with Android sources unchanged at
`cf3635008773a5a14d0a4d8daf7106349c733a87`. JVM XML reports contain 155 tests,
zero failures/errors/skips. All 18 reported transfer sources meet the required
90% line threshold. Instrumentation was compiled, **not executed on a device**.
Raw logs, JaCoCo/JUnit results, baseline details and the full module lint inventory
are retained locally under the remediation evidence line.

Gradle task states such as `NO-SOURCE`, `UP-TO-DATE` and a skipped plugin
configuration-check task are not counts of skipped product test cases. Product
test totals and skips must come from their actual test-result reports.
