#include "llama.h"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>

#if defined(_WIN32)
#define VITALIS_EXPORT extern "C" __declspec(dllexport)
#else
#define VITALIS_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {

struct cancellation_token {
    std::atomic<uint32_t> references{1};
    std::atomic<bool> requested{false};
    std::atomic<bool> acknowledged{false};
};

std::mutex backend_mutex;
std::condition_variable backend_condition;
bool backend_initializing = false;
bool backend_initialized = false;

// Process-wide, not isolate-local. Readers include in-progress loads and all
// retained model mappings; mutation is admitted only after every reader frees.
struct model_access_lease { bool mutation; std::string path; };
struct model_file_access { uint64_t readers = 0; bool mutation = false; };
std::mutex model_access_mutex;
uint64_t model_readers = 0;
uint64_t unknown_model_readers = 0;
uint64_t file_mutations = 0;
bool model_mutation = false;
std::unordered_map<std::string, model_file_access> model_files;

void discard_log(ggml_log_level, const char *, void *) {}

bool abort_when_cancelled(void * opaque) {
    auto * token = static_cast<cancellation_token *>(opaque);
    if (token == nullptr || !token->requested.load(std::memory_order_acquire)) {
        return false;
    }
    token->acknowledged.store(true, std::memory_order_release);
    return true;
}

bool continue_model_load(float, void * opaque) {
    // llama.cpp may invoke this on a loader thread. Both callback and atomic
    // state stay native; false asks the loader to stop and clean up its work.
    return !abort_when_cancelled(opaque);
}

}  // namespace

VITALIS_EXPORT void * vitalis_model_read_acquire() {
    auto * lease = new (std::nothrow) model_access_lease{false, {}};
    if (lease == nullptr) return nullptr;
    std::lock_guard<std::mutex> lock(model_access_mutex);
    if (model_mutation || file_mutations != 0) { delete lease; return nullptr; }
    ++model_readers;
    ++unknown_model_readers;
    return lease;
}

VITALIS_EXPORT void * vitalis_model_mutation_acquire() {
    auto * lease = new (std::nothrow) model_access_lease{true, {}};
    if (lease == nullptr) return nullptr;
    std::lock_guard<std::mutex> lock(model_access_mutex);
    if (model_mutation || model_readers != 0 || file_mutations != 0) { delete lease; return nullptr; }
    model_mutation = true;
    return lease;
}

// Exact canonical file keys are supplied by the filesystem adapter. No paths
// are logged. Unknown readers retain whole-runtime exclusion above.
static void * acquire_model_file(const char * path, bool mutation) {
    if (path == nullptr || *path == '\0') return nullptr;
    model_access_lease * lease = nullptr;
    try {
        lease = new model_access_lease{mutation, path};
        std::lock_guard<std::mutex> lock(model_access_mutex);
        auto found = model_files.find(lease->path);
        const bool occupied = found != model_files.end() &&
            (found->second.mutation || (mutation && found->second.readers != 0));
        if (model_mutation || occupied || (mutation && unknown_model_readers != 0)) {
            delete lease;
            return nullptr;
        }
        auto & file = model_files[lease->path];
        if (mutation) { file.mutation = true; ++file_mutations; }
        else { ++file.readers; ++model_readers; }
        return lease;
    } catch (...) {
        delete lease;
        return nullptr; // Allocation failure never grants unprotected access.
    }
}

VITALIS_EXPORT void * vitalis_model_file_read_acquire(const char * path) {
    return acquire_model_file(path, false);
}

VITALIS_EXPORT void * vitalis_model_file_mutation_acquire(const char * path) {
    return acquire_model_file(path, true);
}

VITALIS_EXPORT void vitalis_model_access_release(void * opaque) {
    auto * lease = static_cast<model_access_lease *>(opaque);
    if (lease == nullptr) return;
    std::lock_guard<std::mutex> lock(model_access_mutex);
    if (lease->path.empty()) {
        if (lease->mutation) model_mutation = false;
        else { --model_readers; --unknown_model_readers; }
    } else {
        auto found = model_files.find(lease->path);
        if (lease->mutation) { found->second.mutation = false; --file_mutations; }
        else { --found->second.readers; --model_readers; }
        if (found->second.readers == 0 && !found->second.mutation) model_files.erase(found);
    }
    delete lease;
}

VITALIS_EXPORT void vitalis_llama_silence_logs() {
    // The callback and its state both live in the native library. llama.cpp may
    // therefore invoke it from any worker thread without entering a Dart isolate.
    llama_log_set(discard_log, nullptr);
}

VITALIS_EXPORT int32_t vitalis_backend_begin_initialization() {
    std::unique_lock<std::mutex> lock(backend_mutex);
    backend_condition.wait(lock, [] { return !backend_initializing; });
    if (backend_initialized) {
        return 0;
    }
    backend_initializing = true;
    return 1;
}

VITALIS_EXPORT void vitalis_backend_finish_initialization(int32_t success) {
    std::lock_guard<std::mutex> lock(backend_mutex);
    if (!backend_initializing) {
        return;
    }
    if (success != 0) {
        llama_backend_init();
        backend_initialized = true;
    }
    backend_initializing = false;
    backend_condition.notify_all();
}

VITALIS_EXPORT int32_t vitalis_backend_is_initialized() {
    std::lock_guard<std::mutex> lock(backend_mutex);
    return backend_initialized ? 1 : 0;
}

VITALIS_EXPORT void * vitalis_cancel_token_create() {
    return new (std::nothrow) cancellation_token();
}

VITALIS_EXPORT llama_progress_callback vitalis_model_load_cancel_callback() {
    return continue_model_load;
}

VITALIS_EXPORT void vitalis_cancel_token_retain(void * opaque) {
    auto * token = static_cast<cancellation_token *>(opaque);
    if (token != nullptr) {
        token->references.fetch_add(1, std::memory_order_relaxed);
    }
}

VITALIS_EXPORT void vitalis_cancel_token_request(void * opaque) {
    auto * token = static_cast<cancellation_token *>(opaque);
    if (token != nullptr) {
        token->requested.store(true, std::memory_order_release);
    }
}

VITALIS_EXPORT int32_t vitalis_cancel_token_is_requested(void * opaque) {
    auto * token = static_cast<cancellation_token *>(opaque);
    if (token == nullptr || !token->requested.load(std::memory_order_acquire)) {
        return 0;
    }
    // Native control polling is also an acknowledgement path. This covers a
    // request observed between decode calls while the abort callback covers a
    // request observed by llama.cpp during a decode.
    token->acknowledged.store(true, std::memory_order_release);
    return 1;
}

VITALIS_EXPORT int32_t vitalis_cancel_token_is_acknowledged(void * opaque) {
    auto * token = static_cast<cancellation_token *>(opaque);
    return token != nullptr && token->acknowledged.load(std::memory_order_acquire);
}

VITALIS_EXPORT void vitalis_cancel_token_destroy(void * opaque) {
    auto * token = static_cast<cancellation_token *>(opaque);
    if (token != nullptr &&
            token->references.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        delete token;
    }
}

VITALIS_EXPORT void vitalis_context_set_cancel_token(
        llama_context * context,
        void * opaque) {
    llama_set_abort_callback(context, abort_when_cancelled, opaque);
}

VITALIS_EXPORT void vitalis_context_clear_cancel_token(llama_context * context) {
    if (context != nullptr) {
        llama_set_abort_callback(context, nullptr, nullptr);
    }
}
