"""Reproducible CSV and image task exports (also runnable in Colab).

Requires numpy, onnx, onnxruntime and Pillow. No app/user data is read.
Usage: python export_reference_tasks.py <new-output-directory>
"""
import hashlib
import json
import pathlib
import sys

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper
import onnxruntime as ort
from PIL import Image

destination = pathlib.Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=False)
ort.disable_telemetry_events()
results = {}

def export(name, graph, input_spec, values, expected):
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 18)])
    model.ir_version = 9
    onnx.checker.check_model(model)
    path = destination / (name + ".onnx")
    onnx.save(model, path)
    session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    output = session.run(None, {input_spec["name"]: values})[0]
    np.testing.assert_allclose(output, expected, rtol=0, atol=1e-6)
    task = {"schema_version": 1, "runtime": "onnx", "name": name,
            "model": {"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()},
            "input": input_spec, "outputs": [graph.output[0].name]}
    (destination / (name + ".task.json")).write_text(json.dumps(task, indent=2), encoding="utf-8")
    results[name] = {"model_sha256": task["model"]["sha256"], "output": output.tolist()}

export("csv_sum", helper.make_graph(
    [helper.make_node("MatMul", ["features", "weights"], ["prediction"])], "csv_sum",
    [helper.make_tensor_value_info("features", TensorProto.FLOAT, [3, 2])],
    [helper.make_tensor_value_info("prediction", TensorProto.FLOAT, [3, 1])],
    [numpy_helper.from_array(np.ones((2, 1), dtype=np.float32), "weights")]),
    {"name": "features", "kind": "csv", "dtype": "float32", "shape": [3, 2], "header": True},
    np.array([[1, 2], [-1, 3], [0, 0]], dtype=np.float32), np.array([[3], [2], [0]], dtype=np.float32))
(destination / "input.csv").write_text("first,second\n1,2\n-1,3\n0,0\n", encoding="utf-8")

pixels = np.array([[[255, 0, 0], [255, 0, 0]], [[0, 255, 0], [0, 0, 255]]], dtype=np.uint8)
Image.fromarray(pixels).save(destination / "input.png")
export("image_mean_rgb", helper.make_graph(
    [helper.make_node("ReduceMean", ["image", "axes"], ["mean_rgb"], keepdims=0)], "image_mean_rgb",
    [helper.make_tensor_value_info("image", TensorProto.FLOAT, [1, 3, 2, 2])],
    [helper.make_tensor_value_info("mean_rgb", TensorProto.FLOAT, [1, 3])],
    [numpy_helper.from_array(np.array([2, 3], dtype=np.int64), "axes")]),
    {"name": "image", "kind": "image", "dtype": "float32", "shape": [1, 3, 2, 2],
     "layout": "NCHW", "color_order": "RGB", "orientation": "stored", "resize": "stretch",
     "interpolation": "nearest", "scale": 1 / 255, "mean": [0, 0, 0], "std": [1, 1, 1]},
    (pixels.astype(np.float32) / 255).transpose(2, 0, 1)[None], np.array([[.5, .25, .25]], dtype=np.float32))
(destination / "reference-results.json").write_text(json.dumps({"status": "HOST_REFERENCE_PASS",
    "onnxruntime": ort.__version__, "results": results}, indent=2), encoding="utf-8")
print(json.dumps(results, indent=2))
