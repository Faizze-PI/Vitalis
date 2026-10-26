#include "llama.h"
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <new>

// Fault only the next allocation in this isolated executable, never real RAM.
static std::atomic<bool> fail_next_allocation{false};
void * operator new(std::size_t size) {
    if (fail_next_allocation.exchange(false)) throw std::bad_alloc();
    if (void * memory = std::malloc(size == 0 ? 1 : size)) return memory;
    throw std::bad_alloc();
}
void operator delete(void * memory) noexcept { std::free(memory); }
void operator delete(void * memory, std::size_t) noexcept { std::free(memory); }

extern "C" void llama_log_set(ggml_log_callback, void *) {}
extern "C" void llama_backend_init() {}
extern "C" void llama_set_abort_callback(llama_context *, ggml_abort_callback, void *) {}
extern "C" void * vitalis_cancel_token_create();
extern "C" void vitalis_cancel_token_destroy(void *);
extern "C" void vitalis_cancel_token_request(void *);
extern "C" int32_t vitalis_cancel_token_is_requested(void *);

int main() {
    fail_next_allocation.store(true);
    void * token = nullptr;
    try {
        token = vitalis_cancel_token_create();
    } catch (...) {
        std::fputs("FAIL: allocation exception escaped cancellation-token ABI\n", stderr);
        return 1;
    }
    if (token != nullptr || fail_next_allocation.load()) {
        std::fputs("FAIL: injected allocation failure did not return null\n", stderr);
        vitalis_cancel_token_destroy(token);
        return 1;
    }
    token = vitalis_cancel_token_create();
    if (token == nullptr) return 2;
    vitalis_cancel_token_request(token);
    if (vitalis_cancel_token_is_requested(token) != 1) return 3;
    vitalis_cancel_token_destroy(token);
    std::puts("Cancellation allocation failure returns null; subsequent token works");
}
