#pragma once
#include <cstddef>
#include <cstdint>

namespace dmc4 {
namespace lzx {

// Decompresses LZX / XMemDecompress compressed stream (Xbox 360 MT Framework).
// windowSize: window size in bytes (defaults to 0x8000 = 32KB, 15 bits window).
// Returns 0 on success, non-zero on error.
int Decompress(const void *src, size_t srcLen, void *dst, size_t dstLen, uint32_t windowSize = 0x8000);

} // namespace lzx
} // namespace dmc4
