#pragma once
#include <cstddef>
#include <cstdint>

namespace dmc4 {
namespace lzx {

// Comprehensive decompressor for Capcom MT Framework ARC archive entries (Xbox 360 & PC).
// Supports:
// 1. XCompress Native container (0x0FF512EE / 0x0FF512ED)
// 2. Raw Deflate (headerless, windowBits = -15)
// 3. Standard Zlib (0x78 header, windowBits = 15)
// 4. Auto zlib / gzip (windowBits = 47)
// 5. Raw XMem LZX (no Intel header, window 32KB..2MB, continuous and 32KB/256KB/512KB partitions)
// 6. XNB chunk-framed LZX (2-byte block framing)
// 7. Standard CAB LZX (with Intel header)
//
// If outMethod != nullptr, receives a static string describing the successful method.
// Returns 0 on success, non-zero on error.
int Decompress(const void *src, size_t srcLen, void *dst, size_t dstLen,
               const char **outMethod = nullptr, uint32_t windowSize = 0x8000);

} // namespace lzx
} // namespace dmc4
