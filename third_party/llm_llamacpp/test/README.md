# VITALIS native text-runtime tests

`vitalis_text_runtime_gate_test.dart` is the release-declared native integration
gate. It requires a real, locally cached copy of the immutable bundled Qwen GGUF
through `VITALIS_TEST_MODEL`; absence of the model is a failure, not a skip.

The gate proves:

- native model/context initialization and tokenizer access;
- visible text generation and native completion metrics;
- cancellation acknowledgement within two seconds;
- runtime recovery and a successful request immediately after cancellation.

Example on PowerShell:

```powershell
$env:VITALIS_TEST_MODEL = 'D:\model-cache\bundled-qwen.gguf'
dart test test\vitalis_text_runtime_gate_test.dart
```

The supplied file must first be checked against the bundled-model manifest's
immutable revision and SHA-256. Test output alone is not authority for an
unverified model file.

The remaining unit and historical integration fixtures help maintain the
vendored adapter but are not evidence for product features that VITALIS does
not ship. In particular, VITALIS does not support vision input, Ollama model
discovery, arbitrary GPU-layer values, or cloud inference. Vulkan is validated
only by each platform's separate experimental gate.
