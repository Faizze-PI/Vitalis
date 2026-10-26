import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/context_planner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String modelPath;
  late LlamaCppChatRepository repository;
  late LlamaCppModelLoader loader;
  late LlamaCppModel oracleModel;
  late LlamaBindings bindings;

  setUpAll(() async {
    modelPath = Platform.environment['VITALIS_TEST_MODEL'] ?? '';
    expect(modelPath, isNotEmpty, reason: 'VITALIS_TEST_MODEL is mandatory');
    expect(
      (await sha256.bind(File(modelPath).openRead()).first).toString(),
      BundledModelManifest.sha256,
    );
    repository = LlamaCppChatRepository.withModelPath(
      modelPath,
      contextSize: 2048,
      batchSize: 128,
      threads: 2,
    );
    await repository.prepare();
    loader = LlamaCppModelLoader();
    oracleModel = await loader.loadModel(
      modelPath,
      options: const ModelLoadOptions(vocabOnly: true),
    );
    bindings = LlamaBindings(loadLlamaLibrary());
  });

  tearDownAll(() async {
    loader.dispose();
    await repository.close();
    PersistentInferenceIsolate.instance.dispose();
  });

  const fixtures = {
    'ASCII': 'Repeat exactly: VITALIS LOCAL PASS',
    'accented Latin': 'Été français, Straße, mañana, ação. END OF MESSAGE',
    'CJK': '请保留完整消息。日本語と한국어。END OF MESSAGE',
    'emoji': '😀🧠🛠️👩🏽‍💻🧪🚀 END OF MESSAGE',
    'Hindi': 'यह पूरा संदेश सुरक्षित रहना चाहिए। END OF MESSAGE',
  };
  test(
    'planner caps output using the real multilingual template count',
    () async {
      final result = await ContextPlanner(LlamaContextTokenCounter(repository))
          .plan(
            systemPrompt: 'Answer briefly.',
            attachedNotes: [],
            messages: [
              Message(
                chatId: 1,
                role: MessageRole.user,
                content: '你好 😀 café नमस्ते',
              ),
            ],
            profile: const RuntimeProfile(
              contextSize: 2048,
              reservedOutputTokens: 2048,
              generationThreads: 2,
              promptThreads: 2,
              batchSize: 128,
              gpuLayers: 0,
              thinkingMode: ThinkingMode.off,
            ),
          );
      final counted = await repository.countChatTokens([
        for (final entry in result.context)
          LLMMessage(
            role: entry['role'] == 'system' ? LLMRole.system : LLMRole.user,
            content: entry['content'],
          ),
      ]);
      expect(counted, greaterThan(0));
      expect(result.promptTokens, counted);
      expect(result.reservedOutputTokens, 2048 - counted);
      expect(result.reservedOutputTokens, greaterThan(0));
    },
  );
  for (final entry in fixtures.entries) {
    test(
      'chat token count includes the complete ${entry.key} template',
      () async {
        final expected = _countNative(
          bindings,
          oracleModel,
          _renderNativeTemplate(bindings, oracleModel, entry.value),
        );
        final actual = await repository.countChatTokens([
          LLMMessage(role: LLMRole.user, content: entry.value),
        ]);
        expect(actual, expected);
      },
    );
  }

  test(
    'generation evaluates every UTF-8 byte of an above-batch prompt',
    () async {
      final prompt =
          '${List.filled(70, '你好世界 😀 café').join(' ')}\n'
          'Reply with one word: hello.';
      final expected = _countNative(
        bindings,
        oracleModel,
        _renderNativeTemplate(bindings, oracleModel, prompt),
      );
      expect(expected, greaterThan(repository.batchSize));
      var completions = 0;
      await for (final event in repository.streamChatWithGenerationOptions(
        'unicode-fixture',
        messages: [LLMMessage(role: LLMRole.user, content: prompt)],
        generationOptions: const GenerationOptions(maxTokens: 1),
      )) {
        if (event.done == true) completions++;
      }
      expect(completions, 1);
      expect(repository.lastMetrics?.promptTokens, expected);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

int _countNative(LlamaBindings bindings, LlamaCppModel model, String text) {
  final pointer = text.toNativeUtf8();
  final token = calloc<ffi.Int32>();
  try {
    final result = bindings.llama_tokenize(
      model.vocab,
      pointer.cast(),
      utf8.encode(text).length,
      token,
      0,
      true,
      true,
    );
    return result < 0 ? -result : result;
  } finally {
    calloc.free(token);
    calloc.free(pointer);
  }
}

String _renderNativeTemplate(
  LlamaBindings bindings,
  LlamaCppModel model,
  String content,
) {
  final message = calloc<llama_chat_message>();
  final role = 'user'.toNativeUtf8();
  final body = content.toNativeUtf8();
  message.ref
    ..role = role.cast()
    ..content = body.cast();
  try {
    final template = bindings.llama_model_chat_template(
      model.pointer,
      ffi.nullptr,
    );
    final size = bindings.llama_chat_apply_template(
      template,
      message,
      1,
      true,
      ffi.nullptr,
      0,
    );
    expect(size, greaterThan(0));
    final buffer = calloc<ffi.Char>(size + 1);
    try {
      final written = bindings.llama_chat_apply_template(
        template,
        message,
        1,
        true,
        buffer,
        size + 1,
      );
      expect(written, size);
      return buffer.cast<Utf8>().toDartString(length: written);
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(body);
    calloc.free(role);
    calloc.free(message);
  }
}
