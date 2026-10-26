# Privacy boundaries

Conversations, notes, personas and settings are stored locally. Inference uses a local GGUF model; the app does not use cloud inference as a fallback.

Public model search/download is a network feature. Search text, model identifiers and ordinary HTTPS connection information, including the requesting IP address, are visible to Hugging Face and its download hosts. These requests do not include saved conversations, notes, personas, prompts or private model paths.

Diagnostics and exported conversations can contain sensitive information. Keep raw logs, databases, screenshots and clipboard exports private, and redact them before sharing. Local processing does not make voluntarily exported or shared information private automatically.

The public repository contains source and synthetic test fixtures, not personal device evidence or model weights.
