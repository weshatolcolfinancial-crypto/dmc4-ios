#pragma once
#include <cstddef>
#include <cstdint>

namespace dmc4 {
namespace xmem {

// Native Xbox 360 XMemCompress LZX frame stream decompressor.
// Returns 0 on success, non-zero on error.
int Decompress(const uint8_t *data, size_t compSize, uint8_t *out, size_t decompSize);

} // namespace xmem
} // namespace dmc4
