// Copyright 2026 VITALIS contributors. MIT license; see LICENSE.
#ifndef VITALIS_CHAT_TEMPLATE_H
#define VITALIS_CHAT_TEMPLATE_H
#include <stdint.h>
#if defined(_WIN32)
#define VITALIS_CHAT_API __declspec(dllexport)
#else
#define VITALIS_CHAT_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Stable redacted ABI dispositions; not tuning limits. hardcode: HC-067
enum vitalis_chat_template_error {
    VITALIS_CHAT_INVALID_ARGUMENT = -1,
    VITALIS_CHAT_INVALID_MESSAGES = -2,
    VITALIS_CHAT_OUTPUT_OVERFLOW = -3,
    VITALIS_CHAT_RENDER_FAILED = -4
};
// Returns required UTF-8 bytes, or a negative redacted failure code.
// A null output with zero capacity queries size without writing.
VITALIS_CHAT_API int32_t vitalis_chat_template_render(const char *source,
    const char *messages_json, int32_t thinking, char *output, int32_t capacity);
#ifdef __cplusplus
}
#endif
#endif
