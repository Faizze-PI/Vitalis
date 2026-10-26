import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/third_party/vitalis_chat_template.g.dart';
import 'package:llm_llamacpp/src/verified_thinking_templates.dart';

/// Internal shared rendering path for native token counting and generation.
String applyNativeChatTemplate(
  LlamaBindings bindings,
  ffi.Pointer<llama_model> model,
  List<IsolateMessage> messages, {
  bool? thinking,
}) {
  if (thinking != null) {
    final pointer = bindings.llama_model_chat_template(model, ffi.nullptr);
    if (pointer.address == 0)
      throw StateError('Configured chat template unavailable');
    final template = pointer.cast<Utf8>().toDartString();
    if (!VerifiedThinkingTemplates.supports(template)) {
      throw StateError('Thinking template capability is unverified');
    }
    final source = template.toNativeUtf8();
    final json = jsonEncode([
      for (final message in messages)
        {'role': message.role, 'content': message.content},
    ]).toNativeUtf8();
    try {
      final size = vitalis_chat_template_render(
        source.cast(),
        json.cast(),
        thinking ? 1 : 0,
        ffi.nullptr,
        0,
      );
      if (size <= 0) throw StateError('Configured template failed ($size)');
      final output = calloc<ffi.Char>(size);
      try {
        final written = vitalis_chat_template_render(
          source.cast(),
          json.cast(),
          thinking ? 1 : 0,
          output,
          size,
        );
        if (written != size)
          throw StateError('Configured template size changed');
        return output.cast<Utf8>().toDartString(length: written);
      } finally {
        calloc.free(output);
      }
    } finally {
      calloc.free(source);
      calloc.free(json);
    }
  }
  final chatMessages = calloc<llama_chat_message>(messages.length);
  final allocatedPointers = <ffi.Pointer<Utf8>>[];

  try {
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final rolePtr = msg.role.toNativeUtf8();
      final contentPtr = msg.content.toNativeUtf8();
      allocatedPointers.add(rolePtr);
      allocatedPointers.add(contentPtr);

      chatMessages[i].role = rolePtr.cast();
      chatMessages[i].content = contentPtr.cast();
    }

    final tmplPtr = bindings.llama_model_chat_template(model, ffi.nullptr);
    if (tmplPtr.address == 0) {
      throw InferenceException(message: 'Model chat template unavailable');
    }

    final requiredSize = bindings.llama_chat_apply_template(
      tmplPtr,
      chatMessages,
      messages.length,
      true,
      ffi.nullptr,
      0,
    );

    if (requiredSize <= 0) {
      throw InferenceException(message: 'Native chat template query failed');
    }

    final buffer = calloc<ffi.Char>(requiredSize + 1);
    try {
      final actualSize = bindings.llama_chat_apply_template(
        tmplPtr,
        chatMessages,
        messages.length,
        true,
        buffer,
        requiredSize + 1,
      );

      if (actualSize <= 0) {
        throw InferenceException(
          message: 'Native chat template rendering failed',
        );
      }
      if (actualSize != requiredSize) {
        throw InferenceException(message: 'Native chat template size changed');
      }

      return buffer.cast<Utf8>().toDartString(length: actualSize);
    } finally {
      calloc.free(buffer);
    }
  } finally {
    for (final ptr in allocatedPointers) {
      calloc.free(ptr);
    }
    calloc.free(chatMessages);
  }
}
