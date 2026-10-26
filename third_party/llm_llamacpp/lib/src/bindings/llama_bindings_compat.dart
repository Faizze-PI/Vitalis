import 'dart:collection';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'llama_bindings.dart';

/// Compatibility helpers for the adapter-list API introduced by llama.cpp.
///
/// The public Dart wrapper historically exposed add/remove/clear operations.
/// Pinned llama.cpp b10727 replaces those native calls with one atomic
/// `llama_set_adapters_lora` operation, so this extension retains the applied
/// set per native context and submits the complete list on every change.
extension LlamaBindingsAdapterCompatibility on LlamaBindings {
  static final Map<int, LinkedHashMap<int, _AppliedAdapter>> _byContext = {};

  int llama_set_adapter_lora(
    ffi.Pointer<llama_context> context,
    ffi.Pointer<llama_adapter_lora> adapter,
    double scale,
  ) {
    final adapters = _byContext.putIfAbsent(
      context.address,
      LinkedHashMap<int, _AppliedAdapter>.new,
    );
    adapters[adapter.address] = _AppliedAdapter(adapter, scale);
    return _applyAdapters(context, adapters.values);
  }

  int llama_rm_adapter_lora(
    ffi.Pointer<llama_context> context,
    ffi.Pointer<llama_adapter_lora> adapter,
  ) {
    final adapters = _byContext[context.address];
    adapters?.remove(adapter.address);
    if (adapters == null || adapters.isEmpty) {
      _byContext.remove(context.address);
      return llama_set_adapters_lora(context, ffi.nullptr, 0, ffi.nullptr);
    }
    return _applyAdapters(context, adapters.values);
  }

  void llama_clear_adapter_lora(ffi.Pointer<llama_context> context) {
    _byContext.remove(context.address);
    llama_set_adapters_lora(context, ffi.nullptr, 0, ffi.nullptr);
  }

  int _applyAdapters(
    ffi.Pointer<llama_context> context,
    Iterable<_AppliedAdapter> values,
  ) {
    final entries = values.toList(growable: false);
    final adapters = calloc<ffi.Pointer<llama_adapter_lora>>(entries.length);
    final scales = calloc<ffi.Float>(entries.length);
    try {
      for (var index = 0; index < entries.length; index++) {
        adapters[index] = entries[index].pointer;
        scales[index] = entries[index].scale;
      }
      return llama_set_adapters_lora(context, adapters, entries.length, scales);
    } finally {
      calloc.free(scales);
      calloc.free(adapters);
    }
  }
}

final class _AppliedAdapter {
  const _AppliedAdapter(this.pointer, this.scale);

  final ffi.Pointer<llama_adapter_lora> pointer;
  final double scale;
}
