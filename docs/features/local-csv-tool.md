# Local CSV column analysis

Select Saved → Files and algorithms → Analyze CSV. Choose an imported CSV,
a one-based column number and whether its first row is a header. Calculate
returns row count, compensated sum, minimum, maximum and mean. Changing a
selection clears the previous result. Invalid input is actionable and retryable.

This explicit local tool addresses the observed incorrect chat calculation
(6 instead of 5 for 2+3+0). It does not repair the model's arithmetic or silently
substitute a tool answer into a conversation. Automatic model tool-calling is
still pending backend validation and a separately controlled execution loop.

The service reuses SHA-256/length-checked workspace extraction and the existing
1 MiB text processing budget. Parsing/calculation runs in a separate Dart isolate.
The ONNX CSV adapter and statistics tool share the same parser. Quoted commas,
escaped quotes, embedded newlines, BOM and CRLF/LF are supported. All rows must
have the same number of columns. Selected cells must be finite numbers; blanks,
formulas, missing data, invalid columns, malformed quotes and overflow fail.
No input is changed, uploaded, evaluated as code, or written into chat history.
Floating-point rounding still applies; arbitrary-precision decimal arithmetic
is not claimed. These bounded calculations do not load or reserve an AI model.

Tests cover known totals, mixed signs, quoting, header choice, numerical
cancellation, invalid input, corrupted file bytes, empty/busy/error/retry UI and
late completion after screen disposal. Thirty-three focused tests passed,
including pre-existing ONNX CSV contracts. The first screen test harness stalled
on file I/O under the widget fake clock; that attempt is retained. Screen tests
now inject the calculation service; the service tests retain real filesystem,
hash verification and worker-isolate execution.

Phone build `b881d25` passed explicit column 2 (sum 5), column 1 (sum 0),
invalid-column rejection, correction/retry, header-off text rejection and header
restoration/retry on OPPO API 36. Seventeen inventory entries matched before/after
the certificate-matched in-place update. No data clearing was used. Full expanded
Android qualification and automatic model tool calling remain incomplete.
CSV parsing follows the quoting model in RFC 4180:
https://www.rfc-editor.org/rfc/rfc4180
Isolate execution follows Dart's supported API:
https://api.dart.dev/dart-isolate/Isolate/run.html

Full root rerun: 1,488 passed with seed 20261104; full analysis clean;
hardcode verifier passed 80 dispositions. Phone validation remains pending.
