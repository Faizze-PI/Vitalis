# VITALIS developer handoff

This handbook explains what the project contains, why each subsystem exists, how requests move through it, and what remains to be qualified. Start here when onboarding a developer or presenting the architecture.

**Source baseline:** `810e58af87ce43b6c9f9c85ca2a9dfb7b7583368`, app `1.0.1+2`, database schema **8**. Documentation describes source behaviour, not proof that every platform acceptance gate has passed. Android and Windows downloads remain previews. CI was still being repaired and evaluated when this handoff began.

## Reading order

1. [Architecture and developer guide](GUIDE.md): responsibilities, flows, data, safety, operations and future scope.
2. [Complete module reference](MODULES.md): every maintained application, native, platform and tooling source file, its purpose, symbols and source references.
3. [Dependencies](DEPENDENCIES.md): why packages and build tools are present, exact resolved versions, direct and transitive inventories.
4. [Test map](TESTS.md): test files and the behaviours they declare; this is an inventory, not a passing-test report.
5. [Source inventory](source-inventory.json): machine-readable paths, roles, source hashes and declarations for the documented checkpoint.
6. [Practical tasks and developer questions](DEVELOPER_TASKS.md): where to change a setting, database, model/template, download path or UI, plus a troubleshooting guide.

For current outcomes use [Actions](https://github.com/Faizze-PI/Vitalis/actions), [open issues](https://github.com/Faizze-PI/Vitalis/issues), the [qualification board](https://github.com/users/Faizze-PI/projects/5/views/2), and [preview status](../public/STATUS.md). Historical test counts are not fresh results for this documentation checkpoint.

## A two-minute explanation

VITALIS is a Flutter conversation app that runs a downloaded GGUF language model locally. Flutter supplies the interface; Provider connects screens to state; SQLite stores conversations and model records; a dedicated Dart isolate drives llama.cpp through FFI. Android Java code handles operating-system services such as durable downloads, notifications and safety telemetry. The Windows C++ runner hosts Flutter and exposes desktop telemetry. Hugging Face supplies public model discovery and downloads, not cloud inference.

The important engineering work is ownership and recovery: only one native operation may own the model/context, cancellation must be acknowledged, installation must not damage an existing model, and interrupted work must retain enough durable state to recover safely.

## Suggested walkthrough for a developer meeting

- **Product:** show a conversation, notes, persona selection and Model Library. Explain that a persona changes instructions; a note supplies additional context; neither trains the model.
- **Code:** open `lib/main.dart`, `lib/widgets/vitalis_dependencies.dart`, then follow one message through `ChatProvider`, `GenerationProvider`, `ContextPlanner` and the native repository.
- **Persistence:** show schema 8, per-chat model settings and the installation journal. Explain why a download finishing is different from a model becoming usable.
- **Native safety:** show the reservation, cancellation and recovery classes. Explain why a timeout cannot mean that native work has stopped.
- **Delivery:** show actual Actions logs, the release provenance, open qualification issues and the project board. Separate implemented behaviour from measured acceptance.
- **Future:** close correctness and qualification first; evaluate GPU and additional platforms separately. Do not promise unsupported platforms from generic package metadata.
