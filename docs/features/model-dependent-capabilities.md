# Model-dependent vision and tools

User clarification, 4 November 2026: vision and tool calling belong to the
selected model and its supported runtime, rather than universal app switches.
The manual CSV calculator and image previews remain useful independent actions;
neither establishes a model's vision or function-calling capability.

Enable an input/action only after the complete path is established:

- Publisher/model metadata declares the relevant capability; names and file
  extensions alone never establish it.
- The installed immutable model revision, quantization and required companion
  artifacts are validated and matched to one model bundle.
- The selected backend implements its architecture, encoder and actual template.
- A functional probe verifies that capability with this bundle/backend. Tool
  calling additionally requires a schema/call/result round trip and an explicitly
  registered local executor; generated code is not automatically executable.

Model changes must refresh capability controls, cancel acknowledged owned work
and invalidate incompatible context/cache state. Missing companion files or
backend support must produce a concrete unavailable reason. Text-only models
must retain text use without appearing vision-capable. Unsupported thinking,
audio, video and tools must not be implied by a generic omni label. File selection
can remain available for storage/preview while the chosen model cannot analyze
that file. Capability records will need independent declared and verified states,
bound to model/companion hashes, template and backend version.

## LFM3-Omni-2B compatibility finding

The publisher's GGUF card currently identifies architecture `lfm3`, a vision/audio
projector and llama.cpp b11960 (v0.8.0) or newer. It describes text, image, audio
and video input and text/speech output. The original card says this is a
non-reasoning model; a thinking toggle must not be presented as supported.

VITALIS is locked to b10727, commit
`ab0b3bd3c846839e9014c03b071f0f550a57ca84`. The inspected architecture table has
`lfm2` and `lfm2moe`, but no `lfm3`. Therefore LFM3 support is currently unavailable,
not verified by the existing Qwen/ONNX tests. Do not infer that an ONNX export of
this multimodal model fits the single-file float32 algorithm runner either.

Next gate: evaluate an immutable newer native source in an isolated probe; review
its ABI/bindings, package dependencies, architecture/encoder and template changes;
then verify text/vision/cancellation and existing-model regressions before changing
the production native lock. Download and test the matched LFM bundle only after
that backend compatibility gate. Audio/video support needs its own decoder and
runtime evidence even when the model itself declares those modalities.

Publisher references checked on 4 November 2026:
- https://huggingface.co/LiquidAI/LFM3-Omni-2B-GGUF
- https://huggingface.co/LiquidAI/LFM3-Omni-2B

This document is an integration requirement and compatibility finding, not a
claim that multimodal inference or automatic tool calling has been enabled.
