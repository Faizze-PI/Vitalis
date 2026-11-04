# Imported image previews

In Files and algorithms, tap an imported PNG/JPEG to see a bounded thumbnail and
source dimensions. This is a file preview; it does not enable GGUF image analysis.
The original and its metadata remain intact. The dialog owns and disposes its
decoded image, including navigation/disposal races. Decoder errors are visible.

Length and streaming SHA-256 are checked first. PNG/JPEG signatures are explicit.
A native image descriptor checks source dimensions before codec creation. The
preview accepts at most 32 MiB encoded bytes and 24 × 1024² source pixels; its
longest decoded edge is at most 1024 pixels without upscaling. Exceeding a preview
budget leaves the stored copy untouched. These are preview resource safeguards,
not model input constraints. Animated PNG is represented by its first frame.
Image orientation/color rendering follows Flutter's decoder; no preprocessing
compatibility or medical interpretation is inferred from the preview.

Tests exercise real PNG/JPEG decoding, aspect-preserving downscaling, byte/pixel
budgets, modified bytes, malformed data and successful decoding after rejection.
Build `f018cec` passed a real PNG preview on OPPO API 36: the RGB fixture was
visually inspected, correct 2×2 dimensions and accessibility label appeared, and
the dialog closed normally. Seventeen upgrade-inventory entries matched. JPEG
remains host-tested only. The scoped app log contained no fatal-pattern matches.

Nine focused tests passed, including PNG/JPEG and workspace regressions. Full
analysis passed. The first hardcode check caught a missing annotation prefix on
the thumbnail edge; corrected annotation is checked separately.

Full root rerun: 1,492 tests passed with seed 20261104. The profile APK built
successfully and was installed in place only after certificate comparison.
Hardcode verification passed 81 dispositions after the annotation correction.
