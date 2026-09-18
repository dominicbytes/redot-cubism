// SPDX-License-Identifier: MIT
#ifndef CUBISM_STRING_HASH_HPP
#define CUBISM_STRING_HASH_HPP
#include <cstdint>

// Preserve the SDK's reverse polynomial, native-char sign and reserved values.
// Unsigned arithmetic defines the intended modulo-2^32 hash on every build.
inline int32_t cubism_string_hash(const char *text, int32_t length, bool singleton_empty) {
    uint32_t bits = 0;
    for (int32_t index = length; index >= 0; --index) {
        bits = bits * 31u + static_cast<uint32_t>(static_cast<int32_t>(text[index]));
    }
    if (bits == UINT32_MAX || singleton_empty) return -2;
    return bits <= INT32_MAX ? static_cast<int32_t>(bits)
                            : -1 - static_cast<int32_t>(UINT32_MAX - bits);
}
#endif
