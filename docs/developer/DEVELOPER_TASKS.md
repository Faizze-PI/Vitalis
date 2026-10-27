# Practical development and explanation notes

Read [GUIDE.md](GUIDE.md) for the architecture and [MODULES.md](MODULES.md) for exact files/types. These examples explain where a change belongs; they do not authorize unrelated product changes or destructive device operations.

## Start a development session

1. Record branch/commit and inspect the worktree. Preserve existing changes.
2. Configure the exact environment in [BUILDING.md](../public/BUILDING.md). Use gate launchers and checkout-local caches.
3. Resolve both lockfiles. Root and vendored packages have separate development dependencies.
4. Reproduce the specific issue and identify its owning layer.
5. Add a regression, implement the smallest complete correction, then run focused and dependent checks.
6. Record what was actually tested. Commit no model weights, databases, private device evidence or signing material.

With the environment already configured, PowerShell examples are:

```powershell
./tool/run_gate.ps1 pub get --enforce-lockfile
Push-Location third_party/llm_llamacpp
try { ../../tool/run_gate.ps1 pub get --enforce-lockfile } finally { Pop-Location }
./tool/run_gate.ps1 analyze
./tool/run_gate.ps1 test
```

POSIX equivalents use `tool/run_gate.sh`. Native suites additionally require the verified model fixture and correct host library-search environment; use the maintained CI steps as the current source, not generic example-app launch instructions. Native build failures must not be hidden behind skipped tests.

## Add or change a generation setting

Trace `ModelSettings` -> defaults/database mapping -> `RuntimeProfile` -> native `GenerationOptions`/repository configuration -> the per-chat settings section and validated editor. Check whether the setting affects template rendering, token budgets, prefix-cache validity or profile-cache identity. If it changes persisted structure, add a real schema migration and historical fixtures. Show both requested and effective values where they can differ. Test invalid bounds, storage/restart and proof that native execution received the value.

## Change notes or persona behaviour

Start in the relevant provider and database mapping, not by concatenating more text in a widget. ChatProvider and ContextPlanner must see the committed change. Verify ordered note attachments, one persona association, storage limits, prompt-token budgets and cache invalidation. Existing saved text must not be silently shortened to fit inference.

## Support a model/template family

Inspect GGUF architecture, tokenizer, template, training context and native capability. A familiar filename is not a verified template. Run the bounded compatibility probe and native tokenizer/generation tests. Thinking controls need audited template support; do not add a UI switch that merely strips generated reasoning. Keep the publisher's model licence and immutable artifact/hash authority visible. Do not add catalogue claims from metadata alone.

## Change database structure

Update schema creation and upgrade paths together, keeping schema-8 journal semantics intact or migrating them explicitly. Preserve IDs, relationships, per-chat model selection and all existing content. Test supported old fixtures, interrupted transaction/projection, duplicate rows and rollback. A migration exception must not cause automatic deletion/recreation of `vitalis.db`.

## Change downloads or add a platform transfer adapter

Implement the shared transfer/storage contracts and preserve job/revision/shard identity. Test resumed and ignored ranges, changed validators, `416`, retry/stop interruption, disk shortage, complete shard validation and installation projection. Android writers can outlive Flutter; a Dart cancellation token alone is not acknowledgement. Desktop foreground transfers do not inherit UIDT/WorkManager guarantees.

## Change cancellation or shutdown

Begin with the reservation and owner/request identity. Trace repository, controller/provider, tuning/warmup/probe callers, native token and terminal acknowledgement. Test preparation and token decoding separately, completion-vs-cancel races, disposal, delayed acknowledgement, stale events and successful follow-up only after confirmed cleanup. A timeout or closed stream is not native termination. Keep failure in recovery-required state when it cannot be proven safe.

## Change UI

Use existing theme tokens, routes and providers. Keep business logic out of widget callbacks. Test small screens, keyboard, long content, text scaling, light/dark theme, meaningful accessibility nodes, pending writes, disabled/read-only states, navigation and disposal. Visual truncation must not change stored content. Do not replace Provider/routing merely to redesign a screen.

## Troubleshoot by symptom

| Symptom | Start with | Do not assume |
|---|---|---|
| Blank or indefinite launch | Startup phase trace, StartupShell, database/migration/safety settlement and actual rendered frame | The model is necessarily responsible |
| Model missing after selection | Exact registry ID, selected readiness, complete file/shard set and expected hashes | Any other installed model can be substituted |
| Busy or recovery required | Reservation snapshot, current owner/request, cancellation/cleanup acknowledgement | Clearing a Dart flag stops native decoding |
| Download stalled or restarts | Native manifest/control generation, scheduler disposition, writer lease and Range validators | Deleting every `.part` file is safe recovery |
| Repetitive or odd output | Actual current model/template/options, sampler acceptance and bounded token/event evidence | Every unwanted string should be removed from output |
| Misleading context percentage | Exact rendered token count and ContextPlanResult exclusions | Loaded database message length equals selected model context |
| Memory growth | Consistent PSS/RSS definition, workload milestones and cooldown | Android PSS-labelled-as-RSS and Windows working set are interchangeable |
| Native library missing in host test | Hook target/output and exact loader environment | Downloading a random system DLL/SO fixes packaging safely |
| Portable package guard fails | Actual tracked/untracked diff after generation and install manifest | Resetting/deleting source or weakening the guard is acceptable |

## Questions developers are likely to ask

**Why Flutter and Provider?** The existing cross-platform UI/state code is shared and extensively exercised. Retaining that graph avoids a simultaneous framework/state rewrite while native correctness and qualification are still being closed. This is a rationale for the present boundary, not a claim that other architectures are universally worse.

**Why use native C++ instead of Dart inference?** llama.cpp/GGML provide GGUF tokenizer/model/context/CPU execution. Dart manages product state, transport and UI, while FFI invokes the native implementation. The isolate keeps blocking inference work away from Flutter's UI execution.

**Is this an autonomous agent?** The user-facing product is local conversation with notes/personas/model management. Generic vendored tool-calling classes do not establish a supported autonomous agent or permission to run external actions.

**Are notes retrieval-augmented generation?** They are explicitly attached context. There is no documented vector index/embedding retrieval pipeline in the current product. Retrieval would be a separate future feature with budgeting, privacy and relevance tests.

**Does Hugging Face process the chat?** It receives public model search/download requests, not local inference requests containing saved conversations. Voluntary exports or diagnostic sharing are separate privacy decisions.

**Can a user switch models?** Yes: installed model identity is selected explicitly for a chat; runtime handoff must respect active ownership. Missing/unverified models remain unavailable rather than silently switching to another file.

**Does more than 4B mean unsupported?** No. It triggers a large-model warning. Actual format/native compatibility, disk and memory suitability remain separate. Smaller models are not automatically safe.

**Is the preview production ready?** No. Built, unit-tested, downloaded, installed and ratified are different states. Use live acceptance issues and source-linked evidence to answer readiness questions.
