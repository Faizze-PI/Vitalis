"""Prepare the hash-locked MobileNet compatibility fixture outside Git.

Requires numpy, Pillow and onnxruntime. Usage: python script.py <cache-directory>.
The published center-crop accuracy pipeline is not evaluated by this probe.
"""
import hashlib
import json
import pathlib
import sys
import urllib.request

import numpy as np
import onnxruntime as ort
from PIL import Image

lock = json.loads(pathlib.Path(__file__).with_name("pretrained_fixtures.lock.json").read_text())
destination = pathlib.Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
model = destination / lock["filename"]
if not model.exists():
    partial = model.with_suffix(".part")
    if partial.exists():
        raise RuntimeError("Existing partial preserved. Use a fresh directory or review it first.")
    url = "https://huggingface.co/{repository}/resolve/{revision}/{filename}".format(**lock)
    size = 0
    with urllib.request.urlopen(url, timeout=30) as response, partial.open("xb") as output:
        while chunk := response.read(65536):
            size += len(chunk)
            if size > lock["bytes"]:
                raise RuntimeError("Oversized fixture response; partial preserved.")
            output.write(chunk)
    if size != lock["bytes"] or hashlib.sha256(partial.read_bytes()).hexdigest() != lock["sha256"]:
        raise RuntimeError("Fixture size/hash mismatch; partial preserved, model not activated.")
    partial.rename(model)
if model.stat().st_size != lock["bytes"] or hashlib.sha256(model.read_bytes()).hexdigest() != lock["sha256"]:
    raise RuntimeError("Existing fixture does not match the publisher lock.")

pixels = np.array([[[255, 0, 0], [255, 0, 0]], [[0, 255, 0], [0, 0, 255]]], dtype=np.uint8)
Image.fromarray(pixels).save(destination / "input.png")
image = np.asarray(Image.fromarray(pixels).resize((224, 224), Image.Resampling.NEAREST), dtype=np.float64)
values = ((image / 255 - [.485, .456, .406]) / [.229, .224, .225]).astype(np.float32).transpose(2, 0, 1)[None]
ort.disable_telemetry_events()
options = ort.SessionOptions()
options.intra_op_num_threads = options.inter_op_num_threads = 1
session = ort.InferenceSession(str(model), options, providers=["CPUExecutionProvider"])
input_name, output_name = session.get_inputs()[0].name, session.get_outputs()[0].name
result = session.run([output_name], {input_name: values})[0]
assert result.shape == (1, 1000) and np.isfinite(result).all()
task = {"schema_version": 1, "runtime": "onnx", "name": "MobileNetV2 compatibility probe",
        "model": {"file": model.name, "sha256": lock["sha256"]},
        "input": {"name": input_name, "kind": "image", "dtype": "float32", "shape": [1, 3, 224, 224],
                  "layout": "NCHW", "color_order": "RGB", "orientation": "stored", "resize": "stretch",
                  "interpolation": "nearest", "scale": 1 / 255, "mean": [.485, .456, .406], "std": [.229, .224, .225]},
        "outputs": [output_name]}
(destination / "mobilenet.task.json").write_text(json.dumps(task, indent=2), encoding="utf-8")
(destination / "reference-values.json").write_text(json.dumps(result.flatten().tolist()), encoding="utf-8")
print(json.dumps({"model_sha256": lock["sha256"], "output_shape": list(result.shape),
                  "runtime": ort.__version__, "scope": "CPU numeric reference; not accuracy qualification"}))
