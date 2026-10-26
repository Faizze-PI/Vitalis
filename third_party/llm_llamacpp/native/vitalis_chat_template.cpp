// Copyright 2026 VITALIS contributors. MIT license; see LICENSE.
#include "vitalis_chat_template.h"
#include "jinja/parser.h"
#include "json.h"
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>

namespace {
// Only the public template AST is cached; conversation contents never are.
std::mutex template_mutex;
std::string cached_source;
std::unique_ptr<jinja::program> cached_program;
}

VITALIS_CHAT_API int32_t vitalis_chat_template_render(const char *source,
    const char *messages_json, int32_t thinking, char *output, int32_t capacity) {
    if (!source || !messages_json || capacity < 0 || (!output && capacity != 0)) return VITALIS_CHAT_INVALID_ARGUMENT;
    try {
        std::lock_guard<std::mutex> lock(template_mutex);
        if (!cached_program || cached_source != source) {
            std::string replacement_source(source);
            auto parsed = jinja::parse_from_tokens(jinja::lexer().tokenize(source));
            auto replacement = std::make_unique<jinja::program>();
            replacement->body = std::move(parsed.body);
            // Commit both cache fields without allocations after preparation.
            cached_program.swap(replacement);
            cached_source.swap(replacement_source);
        }
        auto messages = common_json::parse(messages_json);
        if (!messages.is_array() || messages.empty()) return VITALIS_CHAT_INVALID_MESSAGES;
        common_json input = {
            {"messages", messages}, {"add_generation_prompt", true},
            {"enable_thinking", thinking != 0}, {"bos_token", ""}, {"eos_token", ""}
        };
        jinja::context context(cached_source);
        jinja::global_from_json(context, input, false);
        jinja::runtime runtime(context);
        auto rendered = jinja::runtime::gather_string_parts(runtime.execute(*cached_program));
        const auto result = rendered->as_string().str();
        if (result.size() > static_cast<size_t>(std::numeric_limits<int32_t>::max())) return VITALIS_CHAT_OUTPUT_OVERFLOW;
        const auto required = static_cast<int32_t>(result.size());
        if (output && capacity >= required) std::memcpy(output, result.data(), result.size());
        return required;
    } catch (...) {
        // Upstream exceptions may contain private message text. Never cross FFI
        // with exceptions or expose their contents to normal diagnostics.
        return VITALIS_CHAT_RENDER_FAILED;
    }
}
