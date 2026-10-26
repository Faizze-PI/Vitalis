import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native sample accepts exactly once; extra accept doubles frequency',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'] ?? '';
      expect(path, isNotEmpty, reason: 'Verified native fixture is mandatory');
      expect(
        (await sha256.bind(File(path).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final loader = LlamaCppModelLoader();
      final model = await loader.loadModel(path);
      addTearDown(loader.dispose);
      final bindings = LlamaBindings(loadLlamaLibrary());
      final params = bindings.llama_context_default_params()
        ..n_ctx = 512
        ..n_batch = 128
        ..n_threads = 2
        ..n_threads_batch = 2;
      final context = bindings.llama_init_from_model(model.pointer, params);
      expect(context.address, isNot(0));
      addTearDown(() => bindings.llama_free(context));
      final token = calloc<ffi.Int32>();
      final text = 'Hello'.toNativeUtf8();
      addTearDown(() {
        calloc.free(token);
        calloc.free(text);
      });
      expect(
        bindings.llama_tokenize(
          model.vocab,
          text.cast(),
          5,
          token,
          1,
          false,
          false,
        ),
        1,
      );
      expect(
        bindings.llama_decode(context, bindings.llama_batch_get_one(token, 1)),
        0,
      );
      final chain = bindings.llama_sampler_chain_init(
        bindings.llama_sampler_chain_default_params(),
      );
      expect(chain.address, isNot(0));
      addTearDown(() => bindings.llama_sampler_free(chain));
      final penalties = bindings.llama_sampler_init_penalties(
        bindings.llama_vocab_n_tokens(model.vocab),
        64,
        1,
        2,
        0,
      );
      expect(penalties.address, isNot(0));
      bindings.llama_sampler_chain_add(chain, penalties);
      bindings.llama_sampler_chain_add(
        chain,
        bindings.llama_sampler_init_greedy(),
      );
      final sampled = bindings.llama_sampler_sample(chain, context, -1);
      final data = calloc<llama_token_data>();
      final candidates = calloc<llama_token_data_array>();
      addTearDown(() {
        calloc.free(data);
        calloc.free(candidates);
      });
      double penalizedLogit() {
        data.ref
          ..id = sampled
          ..logit = 10
          ..p = 0;
        candidates.ref
          ..data = data
          ..size = 1
          ..selected = -1
          ..sorted = false;
        bindings.llama_sampler_apply(penalties, candidates);
        return data.ref.logit;
      }

      expect(penalizedLogit(), 8, reason: 'sample itself must accept once');
      bindings.llama_sampler_accept(chain, sampled);
      expect(
        penalizedLogit(),
        6,
        reason: 'extra accept distorts frequency history',
      );

      // Differential oracle: no product generator/template/sampler helper is
      // used to construct the expected native token sequence.
      const prompt = 'List numbers and their names: 1 one, 2 two, 3';
      String reference({
        required bool duplicateAcceptance,
        double frequency = 2,
        double presence = 0,
      }) {
        final ctx = bindings.llama_init_from_model(model.pointer, params);
        expect(ctx.address, isNot(0));
        final sampler = bindings.llama_sampler_chain_init(
          bindings.llama_sampler_chain_default_params(),
        );
        final input = prompt.toNativeUtf8();
        final ids = calloc<ffi.Int32>(256);
        final piece = calloc<ffi.Char>(4096);
        try {
          bindings.llama_sampler_chain_add(
            sampler,
            bindings.llama_sampler_init_penalties(
              bindings.llama_vocab_n_tokens(model.vocab),
              64,
              1,
              frequency,
              presence,
            ),
          );
          bindings.llama_sampler_chain_add(
            sampler,
            bindings.llama_sampler_init_top_k(40),
          );
          bindings.llama_sampler_chain_add(
            sampler,
            bindings.llama_sampler_init_top_p(0.9, 1),
          );
          bindings.llama_sampler_chain_add(
            sampler,
            bindings.llama_sampler_init_temp(0),
          );
          bindings.llama_sampler_chain_add(
            sampler,
            bindings.llama_sampler_init_dist(42),
          );
          final count = bindings.llama_tokenize(
            model.vocab,
            input.cast(),
            utf8.encode(prompt).length,
            ids,
            256,
            true,
            true,
          );
          expect(count, inInclusiveRange(1, 128));
          expect(
            bindings.llama_decode(
              ctx,
              bindings.llama_batch_get_one(ids, count),
            ),
            0,
          );
          final bytes = <int>[];
          for (var index = 0; index < 32; index++) {
            final id = bindings.llama_sampler_sample(sampler, ctx, -1);
            if (duplicateAcceptance) bindings.llama_sampler_accept(sampler, id);
            if (bindings.llama_vocab_is_eog(model.vocab, id)) break;
            final length = bindings.llama_token_to_piece(
              model.vocab,
              id,
              piece,
              4096,
              0,
              true,
            );
            expect(length, inInclusiveRange(0, 4096));
            bytes.addAll(piece.cast<ffi.Uint8>().asTypedList(length));
            ids[0] = id;
            expect(
              bindings.llama_decode(ctx, bindings.llama_batch_get_one(ids, 1)),
              0,
            );
          }
          return utf8.decode(bytes, allowMalformed: true);
        } finally {
          bindings.llama_sampler_free(sampler);
          bindings.llama_free(ctx);
          calloc.free(input);
          calloc.free(ids);
          calloc.free(piece);
        }
      }

      final expected = reference(duplicateAcceptance: false);
      final broken = reference(duplicateAcceptance: true);
      expect(expected, isNotEmpty);
      expect(
        broken,
        isNot(expected),
        reason: 'Fixture must detect double acceptance',
      );
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      addTearDown(() async {
        await runtime.cancel(null, owner);
        await runtime.drainOwner(owner);
        await runtime.releaseOwnedContext(owner);
      });
      final events = await runtime
          .runInference(
            owner: owner,
            modelPath: path,
            prompt: prompt,
            stopTokens: [],
            contextSize: 512,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            options: const GenerationOptions(
              maxTokens: 32,
              temperature: 0,
              seed: 42,
              frequencyPenalty: 2,
            ),
          )
          .toList();
      expect(
        events.whereType<InferenceToken>().map((event) => event.token).join(),
        expected,
      );
      expect(events.whereType<InferenceComplete>(), hasLength(1));
      for (final penalties in [(0.0, 0.0), (0.0, 2.0), (-1.0, -0.5)]) {
        await runtime.releaseOwnedContext(owner);
        final expected = reference(
          duplicateAcceptance: false,
          frequency: penalties.$1,
          presence: penalties.$2,
        );
        final events = await runtime
            .runInference(
              owner: owner,
              modelPath: path,
              prompt: prompt,
              stopTokens: [],
              contextSize: 512,
              batchSize: 128,
              nGpuLayers: 0,
              threads: 2,
              options: GenerationOptions(
                maxTokens: 32,
                temperature: 0,
                seed: 42,
                frequencyPenalty: penalties.$1,
                presencePenalty: penalties.$2,
              ),
            )
            .toList();
        expect(
          events.whereType<InferenceToken>().map((event) => event.token).join(),
          expected,
          reason: 'Native penalty mapping $penalties',
        );
        expect(events.whereType<InferenceComplete>(), hasLength(1));
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
