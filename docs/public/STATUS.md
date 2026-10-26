# Validation status

Status on 26 October 2026: **Android development preview; complete CPU ratification remains on hold.**

## Retained checks

- The latest full root suite before the final paused-byte correction passed 1,302 tests.
- The paused-byte correction passed 38 download-manager tests and targeted analysis; a fresh arm64 debug build succeeded.
- Physical checks covered saved-content features, note-informed generation, light/dark themes, clipboard export of 130 ordered messages, model browsing, two capable app-downloaded models, and selected transfer controls.
- The paused-job database byte count was verified to match the acknowledged native count after the final correction.

These results have different scopes. They are not a complete fresh release matrix, hosted CI pass, performance comparison or guarantee that all possible bugs have been found.

## Known issues / incomplete gates

- Installation recovery authorities and journal integration need further reconciliation and interruption testing.
- An unavailable bundled-model placeholder can appear alongside the installed equivalent.
- The chat model chip uses a generic label instead of displaying the assigned model name.
- Exact-output/instruction adherence needs controlled model/template/sampling characterization; one smoke response differed from the requested marker.
- Restarted cancellation and other durable-transfer failure paths are not fully physically qualified.
- Complete risk coverage, release/lint/artifact inspection, clean-worktree equivalence and support-floor emulator qualification remain incomplete.
- Comparable legacy performance evidence and physical 16-KB page-size validation are not established.
- Vulkan is experimental; desktop rollout is deferred.

No production APK/AAB, signing material, private evidence or model weights are distributed with this source preview. CI is an inactive example because the publication login lacks workflow-writing permission. Automatic Actions are not enabled and no hosted pass is claimed.
