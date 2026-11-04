"""Export a tiny, deliberately long ONNX loop for cancellation tests only.
Never run this model without a native cancellation controller.
Usage: python export_cancellation_fixture.py <fixture-directory>
"""
import hashlib
import pathlib
import sys
import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
path = root / 'cancel_loop.onnx'
if path.exists():
    raise FileExistsError('Existing fixture is preserved')
body = helper.make_graph([
    helper.make_node('Identity', ['condition_in'], ['condition_out']),
    helper.make_node('Add', ['value_in', 'one'], ['value_out']),
], 'bounded_memory_loop', [
    helper.make_tensor_value_info('iteration', TensorProto.INT64, []),
    helper.make_tensor_value_info('condition_in', TensorProto.BOOL, []),
    helper.make_tensor_value_info('value_in', TensorProto.FLOAT, [1, 1]),
], [
    helper.make_tensor_value_info('condition_out', TensorProto.BOOL, []),
    helper.make_tensor_value_info('value_out', TensorProto.FLOAT, [1, 1]),
], [numpy_helper.from_array(np.ones((1, 1), dtype=np.float32), 'one')])
graph = helper.make_graph([
    helper.make_node('Loop', ['iterations', 'condition', 'features'], ['prediction'], body=body),
], 'cancellation_fixture', [helper.make_tensor_value_info('features', TensorProto.FLOAT, [1, 1])],
[helper.make_tensor_value_info('prediction', TensorProto.FLOAT, [1, 1])], [
    numpy_helper.from_array(np.array(1000000000, dtype=np.int64), 'iterations'),
    numpy_helper.from_array(np.array(True), 'condition'),
])
model = helper.make_model(graph, opset_imports=[helper.make_opsetid('', 18)], ir_version=9)
onnx.checker.check_model(model)
onnx.save(model, path)
(root / 'cancel_loop.sha256').write_text(hashlib.sha256(path.read_bytes()).hexdigest() + '\n')
print('Exported cancellation-only fixture; inference intentionally not run here.')
