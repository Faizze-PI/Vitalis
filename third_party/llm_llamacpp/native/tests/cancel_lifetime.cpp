#include "llama.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <atomic>
#include <cassert>
#include <cstring>
#include <thread>

// Compile the actual production bridge against its locked upstream headers.
// No model, backend, or personal filesystem content is used by this fixture.
extern "C" void llama_log_set(ggml_log_callback, void *) {}
extern "C" void llama_backend_init() {}
extern "C" void llama_set_abort_callback(llama_context *, ggml_abort_callback, void *) {}
extern "C" void * vitalis_cancel_token_create();
extern "C" void vitalis_cancel_token_request(void *);
extern "C" int32_t vitalis_cancel_token_is_requested(void *);
extern "C" void vitalis_cancel_token_destroy(void *);
extern "C" int32_t vitalis_cancel_token_is_acknowledged(void *);
extern "C" llama_progress_callback vitalis_model_load_cancel_callback();
extern "C" void * vitalis_model_read_acquire();
extern "C" void * vitalis_model_mutation_acquire();
extern "C" void vitalis_model_access_release(void *);
extern "C" void * vitalis_model_file_read_acquire(const char *);
extern "C" void * vitalis_model_file_mutation_acquire(const char *);
#if VITALIS_CANCEL_REFS
void test_target_file_access() {
    for (int cycle = 0; cycle < 1000; ++cycle) {
        auto * reader = vitalis_model_file_read_acquire("file-a");
        assert(reader != nullptr);
        assert(vitalis_model_file_mutation_acquire("file-a") == nullptr);
        auto * mutation = vitalis_model_file_mutation_acquire("file-b");
        assert(mutation != nullptr);
        std::thread competitor([] {
            auto * unrelated = vitalis_model_file_read_acquire("file-a");
            assert(unrelated != nullptr);
            vitalis_model_access_release(unrelated);
            assert(vitalis_model_file_read_acquire("file-b") == nullptr);
        });
        competitor.join();
        assert(vitalis_model_mutation_acquire() == nullptr);
        assert(vitalis_model_read_acquire() == nullptr);
        vitalis_model_access_release(mutation);
        vitalis_model_access_release(reader);
        auto * next = vitalis_model_mutation_acquire();
        assert(next != nullptr);
        vitalis_model_access_release(next);
    }
}
extern "C" void vitalis_cancel_token_retain(void *);
#endif

int main(int argc, char ** argv) {
    if (argc == 2 && std::strcmp(argv[1], "--unsafe-reproduction") == 0) {
        // Original helper publishes an address, finishes, and frees it before
        // the receiver services queued Stop. ASan must reject this sequence.
        void * token = vitalis_cancel_token_create();
        vitalis_cancel_token_destroy(token);
        vitalis_cancel_token_request(token);
        return 0;
    }
#if VITALIS_CANCEL_REFS
    test_target_file_access();
    for (int cycle = 0; cycle < 1000; ++cycle) {
        auto * first = vitalis_model_read_acquire();
        auto * second = vitalis_model_read_acquire();
        assert(first != nullptr && second != nullptr);
        assert(vitalis_model_mutation_acquire() == nullptr);
        vitalis_model_access_release(first);
        assert(vitalis_model_mutation_acquire() == nullptr);
        vitalis_model_access_release(second);
        auto * mutation = vitalis_model_mutation_acquire();
        assert(mutation != nullptr);
        std::thread competitor([] {
            assert(vitalis_model_read_acquire() == nullptr);
            assert(vitalis_model_mutation_acquire() == nullptr);
        });
        competitor.join();
        vitalis_model_access_release(mutation);
        auto * next = vitalis_model_read_acquire();
        assert(next != nullptr);
        vitalis_model_access_release(next);
    }
    for (int cycle = 0; cycle < 1000; ++cycle) {
        void * token = vitalis_cancel_token_create();
        auto progress = vitalis_model_load_cancel_callback();
        assert(progress != nullptr);
        assert(progress(0.0f, token));
        // Acquire the transferred reference before publishing the address.
        vitalis_cancel_token_retain(token);
        std::atomic<bool> published{false};
        std::thread helper([&] {
            published.store(true, std::memory_order_release);
            vitalis_cancel_token_destroy(token);
        });
        while (!published.load(std::memory_order_acquire)) std::this_thread::yield();
        vitalis_cancel_token_request(token);
        // Loader callbacks may run on native workers; false is the locked
        // llama.cpp contract for aborting load. No Dart callback participates.
        assert(!progress(0.5f, token));
        assert(vitalis_cancel_token_is_acknowledged(token) != 0);
        assert(vitalis_cancel_token_is_requested(token) != 0);
        helper.join();
        vitalis_cancel_token_destroy(token);
    }
    return 0;
#else
    return 2; // The old bridge is reproduction-only, never an acceptance pass.
#endif
}
