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
  stored. PNG/JPEG have bounded image previews. Unsupported formats show metadata.
- Removal requires confirmation and addresses only the controlled imported copy.
  Leased inputs cannot be removed while a task is using them.

UTF-8 text/CSV chat attachments are implemented and phone-tested separately;
image preview does not enable vision chat. The workspace links to
**Run custom algorithm**. Select an imported task JSON and input; the exact model
is found by its declared SHA-256. No background upload or automatic execution
occurs on import.

## Working prototype

`Saved → Files and algorithms → Import file` imports the JSON description, ONNX
model and input separately. Then choose **Run custom algorithm**, the task JSON,
and the CSV/image. The native CPU runner validates model tensor names and shapes.
Results display named raw tensor values, with a labelled first-64-value preview.

The first adapter supports one float32 input, float32 tensor outputs, numeric CSV,
and opaque PNG/JPEG images. Image tasks explicitly declare RGB, stored orientation
(no EXIF rotation), nearest-neighbour stretch resizing, NCHW/NHWC layout, scale,
mean and standard deviation. Unsupported contracts fail rather than guessing.
Stop requests native cancellation; navigation remains blocked until Run settles.
Backgrounding requests Stop. A loaded chat model is released through its owner
before the existing unloaded-runtime lease admits the ONNX task; chat assignments
are preserved and the next chat request can reload its model.

`tool/custom_tasks/export_reference_tasks.py` generates reproducible model/task/input
files and checks their outputs on the host. It also runs in Colab with numpy,
onnx, onnxruntime and Pillow installed. CSV sum returns `[3, 2, 0]`; the image
channel-mean algorithm returns `[0.5, 0.25, 0.25]`. These are developer reference
algorithms, not trained diagnostic models. Real exports need matching preprocessing
and reference results. The app does not execute notebooks or Python scripts.

## Delivery order

1. Implemented: Android ONNX adapter loads a single-file model, binds named float tensors, runs
   on CPU, close owned resources and acknowledge cancellation. Remove the AAR's
   telemetry initializer and disable telemetry before using the environment.
2. Phone-tested: import a task manifest, its model and a CSV input into the existing workspace.
   Bind model identity by SHA-256; validate input names/types/shapes against the
   actual session. Keep paths under app control.
3. Phone-tested: run selected CSV through its model and display named outputs. Compare
   the phone result to the generated reference fixture.
4. Phone-tested: image preprocessing with explicit configuration and a reference image
   model. Show unsupported operators/missing configuration as errors, not output.
5. Add chat file associations, vision, documents/OCR and controlled tool routing
   through those same file/task contracts.

The first reference graph accepts `features` with two float columns and produces
their sum as `prediction`. Reference rows `[1,2]`, `[-1,3]`, `[0,0]` produced
`[3]`, `[2]`, `[0]` on CPU using ONNX Runtime 1.24.4 on the development host.
Android execution on 1.31.1 produced matching reference outputs in native tests
and through the app screens. Binary fixtures stay outside Git. The
[prototype validation report](onnx-prototype-validation.md) records the scope.

## Android runner foundation

The CPU-only Java runner and reference instrumentation tests execute on the OPPO
with ONNX Runtime Android 1.31.1. Four API-28 Robolectric checks pass: image
preprocessing, cancellation
before admission, rejection of unowned files, and rejection of changed model
bytes before native loading. The tests exposed an overly strict canonical-path
check and missing fake-memory setup; corrected reruns and failed attempts are
retained separately. The task-manifest/CSV parser has 11 passing tests.

The runner hashes the exact bytes it loads, checks named float32 tensor shapes,
closes owned native resources, and detaches cancellation handles only after run
termination. The merged debug manifest excludes the AAR telemetry initializer;
environment telemetry is disabled explicitly. Conservative allocation admission
is not a sandbox or a guarantee against every graph's internal allocation.

The Run screen and shared runtime/file ownership are now connected and reference
CSV/image flows pass on the phone. Host checks:
1,451 root tests, clean full analysis, four Android JVM checks and the existing
78-disposition verifier. A later native test independently observed an active
ONNX JNI run, cancelled it, measured 12.056 ms to worker termination and ran CSV
inference successfully afterward. UI Stop timing remains unmeasured. A real
pretrained MobileNetV2 also runs through the UI; the first 64 displayed scores
match a host reference. See the validation report for exact scope and model lock.

## Current limits

PDF/video processing, companion/external-weight ONNX bundles, arbitrary tensor
types, task result export and chat attachments remain pending. Interrupted
uncommitted file copies are not listed
as installed inputs; resume/cleanup journaling is later work. Do not describe this
file workspace as complete support for every algorithm or file format.
