# One-package algorithm import: implementation in progress

Goal: import one ZIP, select a CSV/image and Run. This is a simpler wrapper over
the existing verified ONNX runner, not arbitrary Python execution. Version one
contains exactly two flat entries: `task.json` and the single ONNX file named in
that description. Task schema/preprocessing/output rules remain those of the
working custom-task runtime. Model-specific vision/tool capabilities are separate.

The package-store foundation is implemented. It reads ZIP entries lazily through
pinned archive 4.6.0, validates entry identities and declared size limits before
streamed extraction, verifies CRCs and the task's model SHA-256, and atomically
renames a staging directory only when complete. Duplicate packages reuse their
ready identity. Existing ready packages and the original ZIP survive failures.
New readers cannot enter a package whose removal is pending; active readers block
removal. Decompression runs in an isolate to keep the UI responsive.

Limits come from the device task budget; the existing 64 KiB metadata policy is
reused. ZIP paths, encrypted content, symbolic links, extra entries, incompatible
task schemas, oversized models and mismatched hashes are rejected. Packages do
not become executable merely because their archive/hash validates: backend tensor
validation and actual inference remain the runner's responsibility.

The working implementation now connects a ZIP picker, named algorithm library,
input selection and native runner. Package execution uses the shared task
cancellation lifecycle and retains a package read lease until native termination.
The library removes only its temporary archive copy after import; originals stay
untouched. Import does not automatically execute or establish model accuracy.
The package library was installed and physically tested on OPPO 472fa620 from
checkpoint 1ef9c2b. Import and execution of a Colab-exported image classifier
passed for two public samples, with output parity against Colab within 0.0001.
Returning to the library retained the package; process-restart and removal
qualification remain pending. This does not establish medical accuracy or
complete Android qualification.
Interrupted `.part` directories remain invisible and preserve evidence; automatic
recovery/cleanup policy must be completed before final qualification.

Foundation verification: 11 focused tests and 1,504 full root tests passed with
seed 20261104; analysis clean; hardcode verifier passed 82 dispositions. Initial
test archives accidentally declared a zero-length task entry and were corrected
to use the archive string constructor. The removal/read race and non-file model
entry checks failed before their corrections. Failed runs remain in local evidence.


Accepted demonstration scope (user confirmation, 2026-11-04): a compatible
algorithm must run with its declared input and return correct raw outputs.
Automatic class-name presentation is not required for this working version.
The public classifier produced matching top classes and maximum absolute output
differences of 1.63e-9 and 2.39e-7 against Colab. These two cases establish
execution/parity only, not medical accuracy. Scoped pre/post-install inventory
matched in all 17 recorded entries; complete Android qualification remains open.
