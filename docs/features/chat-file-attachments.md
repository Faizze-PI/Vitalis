# Conversation file attachments

Implementation checkpoint, 4 November 2026. Host tests pass; a fresh-build phone
test is still required. The previously installed ONNX prototype does not include
this conversation attachment change.

In a ready chat, use the composer's **+ → Attach file**. Import a local file or
select an existing workspace copy. Its chip remains attached to that chat across
responses and reopening. Removing a chip detaches the reference; it does not
delete the original or workspace copy. The workspace refuses to remove a copy
still referenced by a chat. Deleting a chat leaves its workspace files available.

Schema version 9 adds ordered `chat_file_attachments` references with file ID,
display name, byte size and SHA-256. Existing tables and records are preserved.
The version-8 migration and rollback are exercised using isolated fixtures.
File-reference writes retain the shared workspace read lease, excluding deletion
during their database commit. A removed file cannot acquire a new reference.

For text chats, the first adapter supports UTF-8 TXT, Markdown, CSV, JSON, JSONL
and logs. The reader checks full byte length and SHA-256, then counts the actual
text using the selected model's tokenizer and rendered template. Total extraction
uses the existing 1 MiB text safety budget; larger stored files remain intact.
If selected file content does not fit the context, generation stops with an
explanation rather than answering without it or silently truncating it.

Images/PDF/video can be stored and referenced, but are labelled **Needs decoder**
and cannot be presented as text-model analysis. Their chat processing remains
blocked pending verified adapters. The separate ONNX task runner already accepts
compatible image tasks; it is not GGUF vision chat. There is no in-app training,
Python execution, network upload, or automatic file-triggered tool execution.

Current attachments are conversation-level, not immutable snapshots on each
message. Changing attachments affects future requests/regeneration; it does not
rewrite saved replies. Conversation text export does not package local files.
Do not describe this as complete multimodal or document support.

Host evidence: 1,469 root tests with seed `20261104`, clean full analysis after
removing an unnecessary test import, and 79 registered hardcode dispositions.
Two initial failures were obsolete assertions of database version 8, corrected
to use the authoritative current version while retaining migration tests.

The test-only `AppDataInventoryListener` collects existing database row counts and
canonical content digests plus input-workspace digests before/after an upgrade.
It emits no row text, filenames or model paths. Missing data is reported as
unverified. It is explicitly invoked, not an ordinary JUnit test and not shipped
in the application APK.
