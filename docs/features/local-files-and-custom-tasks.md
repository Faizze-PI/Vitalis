# Local files and custom algorithms: working-first scope

The user reprioritized a working file-to-task flow on 3 November 2026. Generic
file import can proceed before every multimodal backend is qualified; processing
must still be real and must not silently treat unsupported files as readable.

## What the engine must run

VITALIS has two kinds of execution:

- Chat inference: compatible GGUF language/vision models and their required files.
- Custom tasks: compatible exported algorithms/models with declared inputs and
  outputs. ONNX is the first custom-task runtime. A compatible Colab export is a
  model artifact plus its preprocessing/input/output description, not a notebook
  or arbitrary Python script executed by the app.

Numeric CSV can supply feature tensors to regression, classification or other
compatible graphs. Images need declared resize, channel order and normalization;
these cannot be guessed safely from a model filename. Results start as named
output tensors; probabilities, labels and visual overlays need explicit meaning.
No in-app training is included.

## Implemented file slice

`Saved → Files and algorithms` opens a local input workspace:

- Android's existing system picker accepts any file type.
- Bytes are streamed into an app-owned copy, with disk preflight, size validation
  and streaming SHA-256. Original picker files are never modified.
- Atomic per-file metadata makes imports persist. This is a separate store and
  does not rewrite the existing version-8 chat database.
- Text/CSV/JSON previews read only a bounded prefix; the complete file remains
  stored. Other formats currently show metadata, not a fabricated analysis.
- Removal requires confirmation and addresses only the controlled imported copy.
  Leased inputs cannot be removed while a task is using them.

This is not yet attachment injection into chat. There is no custom-task Run button
until the native runner actually executes its selected input. No background upload
or automatic execution occurs on import.

## Next vertical slice

1. Android ONNX adapter: load a single-file model, bind named float tensors, run
   on CPU, close owned resources and acknowledge cancellation. Remove the AAR's
   telemetry initializer and disable telemetry before using the environment.
2. Import a task manifest, its model and a CSV input into the existing workspace.
   Bind model identity by SHA-256; validate input names/types/shapes against the
   actual session. Keep paths under app control.
3. Run the selected CSV through that model and display named outputs. Compare
   the phone result to the generated reference fixture.
4. Add image preprocessing with explicit configuration and a reference image
   model. Show unsupported operators/missing configuration as errors, not output.
5. Add chat file associations, vision, documents/OCR and controlled tool routing
   through those same file/task contracts.

The first reference graph accepts `features` with two float columns and produces
their sum as `prediction`. Reference rows `[1,2]`, `[-1,3]`, `[0,0]` produced
`[3]`, `[2]`, `[0]` on CPU using ONNX Runtime 1.24.4 on the development host.
Android execution remains unverified. The Android candidate is separately pinned
at 1.31.1; matching results must be demonstrated there rather than inferred from
the host. Binary fixtures stay outside Git.

## Current limits

Image/PDF/video decoding, ONNX execution in the app, custom-task import and chat
attachments are still pending. Interrupted uncommitted file copies are not listed
as installed inputs; resume/cleanup journaling is later work. Do not describe this
file workspace as complete support for every algorithm or file format.
