import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/third_party/vitalis_chat_template.g.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/model_descriptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LlamaCppChatRepository repository;
  late LlamaCppModelLoader loader;
  late LlamaCppModel model;
  late LlamaBindings bindings;

  setUpAll(() async {
    final path = Platform.environment['VITALIS_TEST_MODEL'];
    expect(path, isNotNull, reason: 'Immutable native fixture is mandatory');
    expect(
      (await sha256.bind(File(path!).openRead()).first).toString(),
      BundledModelManifest.sha256,
    );
    repository = LlamaCppChatRepository.withModelPath(
      path,
      contextSize: 2048,
      batchSize: 128,
      threads: 2,
      supportsThinkingControl: true,
    );
    await repository.prepare();
    loader = LlamaCppModelLoader();
    model = await loader.loadModel(
      path,
      options: const ModelLoadOptions(vocabOnly: true),
    );
    bindings = LlamaBindings(loadLlamaLibrary());
    final template = bindings
        .llama_model_chat_template(model.pointer, ffi.nullptr)
        .cast<Utf8>()
        .toDartString();
    expect(
      ModelDescriptor.fromMap({
        'id': 'fixture',
        'display_name': 'Fixture',
        'source': 'fixture',
        'compatibility_status': 'compatible',
        'supports_thinking': 1,
        'chat_template': template,
      }).supportsThinking,
      isTrue,
    );
  });
  tearDownAll(() async {
    loader.dispose();
    await repository.close();
  });

  for (final thinking in [false, true]) {
    for (final content in ['Hello.', '你好 😀 café नमस्ते']) {
      test(
        'Qwen3.5 thinking $thinking counts and decodes its branch: $content',
        () async {
          // Hand-derived from the SHA-verified embedded template for one text user
          // message, no tools/system/history. Never derive expected via the SUT.
          final base =
              '<|im_start|>user\n$content<|im_end|>\n<|im_start|>assistant\n';
          final expected = thinking
              ? '$base<think>\n'
              : '$base<think>\n\n</think>\n\n';
          expect(
            _renderConfigured(bindings, model, [
              LLMMessage(role: LLMRole.user, content: content),
            ], thinking),
            expected,
          );
          final text = expected.toNativeUtf8();
          final probe = calloc<ffi.Int32>();
          try {
            final native = bindings.llama_tokenize(
              model.vocab,
              text.cast(),
              utf8.encode(expected).length,
              probe,
              0,
              true,
              true,
            );
            expect(native, lessThan(0));
            final actual = await repository.countChatTokens([
              LLMMessage(role: LLMRole.user, content: content),
            ], think: thinking);
            expect(actual, -native);
            await for (final _ in repository.streamChatWithGenerationOptions(
              'thinking-contract',
              messages: [LLMMessage(role: LLMRole.user, content: content)],
              think: thinking,
              generationOptions: const GenerationOptions(maxTokens: 1),
            )) {}
            expect(repository.lastMetrics?.promptTokens, -native);
          } finally {
            calloc.free(text);
            calloc.free(probe);
          }
        },
      );
    }
    test(
      'Qwen3.5 thinking $thinking renders history without mutating replies',
      () async {
        const savedReply = '<think>old reasoning</think>\n\nAnswer.';
        final messages = [
          LLMMessage(role: LLMRole.user, content: 'First.'),
          LLMMessage(role: LLMRole.assistant, content: savedReply),
          LLMMessage(role: LLMRole.user, content: 'Next.'),
        ];
        const base =
            '<|im_start|>user\nFirst.<|im_end|>\n'
            '<|im_start|>assistant\nAnswer.<|im_end|>\n'
            '<|im_start|>user\nNext.<|im_end|>\n<|im_start|>assistant\n';
        final expected = thinking
            ? '$base<think>\n'
            : '$base<think>\n\n</think>\n\n';
        expect(
          _renderConfigured(bindings, model, messages, thinking),
          expected,
        );
        final count = await repository.countChatTokens(
          messages,
          think: thinking,
        );
        await for (final _ in repository.streamChatWithGenerationOptions(
          'thinking-history-contract',
          messages: messages,
          think: thinking,
          generationOptions: const GenerationOptions(maxTokens: 1),
        )) {}
        expect(repository.lastMetrics?.promptTokens, count);
        expect(messages[1].content, savedReply);
      },
    );
  }

  test(
    'template ABI reports size without overwriting an insufficient buffer',
    () {
      final source = '{{ messages[0].content }}'.toNativeUtf8();
      final messages = '[{"role":"user","content":"hello"}]'.toNativeUtf8();
      final buffer = calloc<ffi.Uint8>(2);
      try {
        buffer[0] = 81;
        buffer[1] = 82;
        expect(
          vitalis_chat_template_render(
            source.cast(),
            messages.cast(),
            0,
            buffer.cast(),
            2,
          ),
          5,
        );
        expect([buffer[0], buffer[1]], [81, 82]);
        expect(
          vitalis_chat_template_render(
            source.cast(),
            messages.cast(),
            0,
            ffi.nullptr,
            1,
          ),
          -1,
        );
      } finally {
        calloc.free(source);
        calloc.free(messages);
        calloc.free(buffer);
      }
    },
  );

  test('locked legacy API rejects unknown templates without output', () {
    final template = 'vitalis-unsupported-template-fixture'.toNativeUtf8();
    final role = 'user'.toNativeUtf8();
    final content = 'Harmless test'.toNativeUtf8();
    final messages = calloc<llama_chat_message>(1);
    final buffer = calloc<ffi.Uint8>(32);
    try {
      messages.ref.role = role.cast();
      messages.ref.content = content.cast();
      buffer.asTypedList(32).fillRange(0, 32, 81);
      expect(
        bindings.llama_chat_apply_template(
          template.cast(),
          messages,
          1,
          true,
          buffer.cast(),
          32,
        ),
        -1,
      );
      expect(buffer.asTypedList(32), everyElement(81));
    } finally {
      calloc.free(template);
      calloc.free(role);
      calloc.free(content);
      calloc.free(messages);
      calloc.free(buffer);
    }
  });

  test('template ABI contains malformed input failures without output', () {
    final source = '{{ messages[0].content }}'.toNativeUtf8();
    final messages = '{"private":"SECRET_FIXTURE"'.toNativeUtf8();
    final buffer = calloc<ffi.Uint8>(1);
    try {
      buffer[0] = 81;
      expect(
        vitalis_chat_template_render(
          source.cast(),
          messages.cast(),
          0,
          buffer.cast(),
          1,
        ),
        -4,
      );
      expect(buffer[0], 81);
    } finally {
      calloc.free(source);
      calloc.free(messages);
      calloc.free(buffer);
    }
  });
}

String _renderConfigured(
  LlamaBindings bindings,
  LlamaCppModel model,
  List<LLMMessage> messages,
  bool thinking,
) {
  final source = bindings.llama_model_chat_template(model.pointer, ffi.nullptr);
  final encoded = jsonEncode([
    for (final message in messages)
      {'role': message.role.name, 'content': message.content},
  ]).toNativeUtf8();
  try {
    final size = vitalis_chat_template_render(
      source,
      encoded.cast(),
      thinking ? 1 : 0,
      ffi.nullptr,
      0,
    );
    expect(size, greaterThan(0));
    final output = calloc<ffi.Char>(size);
    try {
      expect(
        vitalis_chat_template_render(
          source,
          encoded.cast(),
          thinking ? 1 : 0,
          output,
          size,
        ),
        size,
      );
      return output.cast<Utf8>().toDartString(length: size);
    } finally {
      calloc.free(output);
    }
  } finally {
    calloc.free(encoded);
  }
}
