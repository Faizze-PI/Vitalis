part of 'persistent_inference_isolate.dart';

/// Configures the sampler chain for text generation.
ffi.Pointer<llama_sampler> _configureSampler(
  LlamaBindings bindings,
  ffi.Pointer<llama_vocab> vocab,
  GenerationOptions options,
) {
  options.validate();
  final samplerParams = bindings.llama_sampler_chain_default_params();
  final sampler = bindings.llama_sampler_chain_init(samplerParams);

  if (options.repeatPenalty != null ||
      options.frequencyPenalty != null ||
      options.presencePenalty != null) {
    final repeatPenalty = options.repeatPenalty ?? 1.0;
    final freqPenalty = options.frequencyPenalty ?? 0.0;
    final presencePenalty = options.presencePenalty ?? 0.0;

    final nVocab = bindings.llama_vocab_n_tokens(vocab);
    bindings.llama_sampler_chain_add(
      sampler,
      bindings.llama_sampler_init_penalties(
        nVocab,
        64, // penalty_last_n: look at last 64 tokens
        repeatPenalty.toDouble(),
        freqPenalty.toDouble(),
        presencePenalty.toDouble(),
      ),
    );
  }

  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_top_k(options.topK),
  );
  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_top_p(options.topP, 1),
  );
  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_temp(options.temperature),
  );

  final seed = options.seed ?? LLAMA_DEFAULT_SEED;
  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_dist(seed),
  );

  return sampler;
}
