# ONNX in VITALIS: explanation and demonstration

## Why ONNX was chosen

VITALIS has two distinct execution paths. llama.cpp handles compatible GGUF language models. ONNX Runtime handles compatible exported prediction models, including numeric CSV and image algorithms. ONNX gives a framework-independent graph format, so a model prepared in Colab can be exported once and executed locally without installing a Python notebook environment on the user's device.

ONNX is the model format; ONNX Runtime is the execution engine. Neither automatically makes every model compatible, accurate, or safe. Exported operators, input types/shapes, preprocessing, and output interpretation must match the implementation.

Official references: [ONNX overview](https://onnx.ai/onnx/intro/), [ONNX Runtime architecture](https://onnxruntime.ai/docs/reference/high-level-design.html), [C++ runtime](https://onnxruntime.ai/docs/get-started/with-cpp.html).

## Implementation in this project

1. Prepare or train a model outside VITALIS, for example in Colab. Export supported operations to `model.onnx` and compare its outputs with the original framework.
2. Create `task.json`: model SHA-256, input tensor name/type/concrete shape, CSV header setting or image preprocessing, and requested output names.
3. Put exactly that metadata and its model into the supported flat algorithm ZIP.
4. In VITALIS, open Saved, Files and algorithms, Algorithms, and import the ZIP. Import validates the structure and hash before committing an app-owned package. Original files remain unchanged.
5. Choose a local CSV or image. VITALIS imports an owned copy. CSV values are checked against the declared dimensions. Images are decoded to RGB, resized with the declared nearest-neighbour method, normalized, and arranged as NHWC or NCHW.
6. The shared task service retains model/input leases and exclusive runtime ownership. It passes the validated contract over `vitalis/custom_tasks` to the platform adapter.
7. Android uses its native ONNX adapter. Windows uses a background C++ worker, Windows Imaging Component, and ONNX Runtime CPU. Windows runtime DLLs ship with the app; Python is not required.
8. The adapter verifies the model hash again, checks actual tensor metadata, executes inference, and returns named float tensors. The app shows raw outputs. Interpretation depends on the exported model; values must not automatically be described as calibrated probabilities.
9. Cancellation requests native termination. Files remain owned until execution returns; late cancelled results are discarded.

## Supported first version

- One concrete float32 input tensor.
- Numeric CSV with explicitly declared rows, columns, and header behavior.
- Single-frame opaque PNG/JPEG images, RGB, stored orientation, stretch resize, nearest interpolation, explicit scale/mean/std, NHWC or NCHW.
- Named float32 output tensors, displayed as raw values.
- CPU execution. Android and Windows runtime versions are recorded separately; matching reference results are tested rather than assuming all versions behave identically.

It does not run arbitrary Python scripts, notebooks, executable plugins, every ONNX model, in-app training, or clinical diagnosis. External-weight bundles, arbitrary tensor types, segmentation visualizations, audio, and custom operators require additional contracts and tests.

## Demonstration to explain aloud

"I exported a prediction graph and its input specification from Colab. VITALIS imports that package, validates its identity, converts the selected file into the exact input tensor, and executes it offline with ONNX Runtime. The returned output is compared with the Colab reference. This demonstrates portable inference, separate from the language-model chat engine."

For the numeric demonstration, the three CSV rows are `[1,2]`, `[-1,3]`, and `[0,0]`; the expected sums are `3`, `2`, and `0`. The RGB demonstration returns channel means `0.5`, `0.25`, and `0.25`. The separate pretrained image classifier demonstration verifies export/execution parity on two public samples; it does not establish medical accuracy or clinical suitability.

## Windows evidence scope

Native Windows CPU CSV inference, image preprocessing, hash/shape rejection, pre-cancellation, and two-image reference parity passed on 2026-11-04. The Windows application-channel integration passed CSV/image package execution; the release bundle passed native dependency checks and was installed and launched locally. See the Windows validation report for remaining qualification limits.
