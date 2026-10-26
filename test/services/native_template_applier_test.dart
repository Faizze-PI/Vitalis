import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/native_template_applier.dart';

void main() {
  const messages = [
    IsolateMessage(role: 'system', content: 'Rules ✓'),
    IsolateMessage(role: 'user', content: 'Hello 👋'),
  ];
  for (final (responses, error) in [
    (<int>[-1], 'Native chat template query failed'),
    (<int>[128, -1], 'Native chat template rendering failed'),
    (<int>[128, 129], 'Native chat template size changed'),
  ]) {
    test('legacy failure $responses rejects guessed output', () {
      final template = 'unsupported fixture template'.toNativeUtf8();
      addTearDown(() => calloc.free(template));
      final bindings = _FailingTemplateBindings(
        responses,
        template: template.cast(),
      );
      expect(
        () => applyNativeChatTemplate(bindings, ffi.nullptr, messages),
        throwsA(
          isA<InferenceException>().having((e) => e.message, 'code', error),
        ),
      );
      expect(bindings.calls, responses.length);
      expect(bindings.observed, [
        for (var i = 0; i < responses.length; i++)
          ['system', 'Rules ✓', 'user', 'Hello 👋'],
      ]);
    });
  }

  test('legacy mode rejects missing template without choosing ChatML', () {
    final bindings = _FailingTemplateBindings([-1]);
    expect(
      () => applyNativeChatTemplate(bindings, ffi.nullptr, messages),
      throwsA(
        isA<InferenceException>().having(
          (e) => e.message,
          'code',
          'Model chat template unavailable',
        ),
      ),
    );
    expect(bindings.calls, 0);
  });

  test('configured mode rejects missing model template before rendering', () {
    final bindings = _FailingTemplateBindings([]);
    expect(
      () => applyNativeChatTemplate(
        bindings,
        ffi.nullptr,
        messages,
        thinking: false,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          'Configured chat template unavailable',
        ),
      ),
    );
    expect(bindings.calls, 0);
  });

  test(
    'configured mode rejects unverified template without legacy fallback',
    () {
      final template = 'unverified fixture template'.toNativeUtf8();
      addTearDown(() => calloc.free(template));
      final bindings = _FailingTemplateBindings([], template: template.cast());
      expect(
        () => applyNativeChatTemplate(
          bindings,
          ffi.nullptr,
          messages,
          thinking: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'code',
            'Thinking template capability is unverified',
          ),
        ),
      );
      expect(bindings.calls, 0);
    },
  );
}

final class _FailingTemplateBindings extends LlamaBindings {
  _FailingTemplateBindings(this.responses, {ffi.Pointer<ffi.Char>? template})
    : template = template ?? ffi.nullptr,
      super(ffi.DynamicLibrary.process());

  final List<int> responses;
  final ffi.Pointer<ffi.Char> template;
  final observed = <List<String>>[];
  var calls = 0;

  @override
  ffi.Pointer<ffi.Char> llama_model_chat_template(
    ffi.Pointer<llama_model> model,
    ffi.Pointer<ffi.Char> name,
  ) => template;

  @override
  int llama_chat_apply_template(
    ffi.Pointer<ffi.Char> tmpl,
    ffi.Pointer<llama_chat_message> chat,
    int nMsg,
    bool addAssistant,
    ffi.Pointer<ffi.Char> buffer,
    int length,
  ) {
    expect(addAssistant, isTrue);
    expect(nMsg, 2);
    expect(buffer.address == 0, calls == 0);
    expect(length, calls == 0 ? 0 : 129);
    observed.add([
      for (var index = 0; index < nMsg; index++) ...[
        chat[index].role.cast<Utf8>().toDartString(),
        chat[index].content.cast<Utf8>().toDartString(),
      ],
    ]);
    return responses[calls++];
  }
}
