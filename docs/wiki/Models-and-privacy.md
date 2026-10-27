# Models and privacy

Inference runs on the device through llama.cpp. There is no cloud inference fallback. Public Hugging Face browsing and downloads do use the network: the service receives search terms, model identifiers and ordinary connection information. Saved conversations are not included in these requests.

The default model is Qwen3.5 0.8B Q4_K_M. Imported models must be compatible GGUF files; a filename alone cannot prove architecture, template support or available memory. Model licences apply independently of VITALIS's Apache-2.0 licence.

Choose an installed model explicitly for a chat. Downloading a model and selecting it for a chat are separate actions. Keep existing models and conversations intact while diagnosing failures; do not use uninstall or data clearing as routine recovery.

Larger models can be slow or exceed memory even when disk space is sufficient. A model below 4B parameters is not automatically safe. CPU is the supported preview path; Vulkan remains experimental and outside the current qualification programme.

Exports, screenshots and diagnostics may contain private information. Keep them local unless reviewed and redacted. See the [privacy boundaries](https://github.com/Faizze-PI/Vitalis/blob/main/docs/public/PRIVACY.md) and [security policy](https://github.com/Faizze-PI/Vitalis/security/policy).
