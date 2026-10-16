#include "xmem_decompress.h"
#include "lzx_decompress.h"

namespace dmc4 {
namespace xmem {

int Decompress(const uint8_t *data, size_t compSize, uint8_t *out, size_t decompSize) {
    if (!data || !out || compSize == 0 || decompSize == 0) return -1;
    return dmc4::lzx::Decompress(data, compSize, out, decompSize);
}

} // namespace xmem
} // namespace dmc4
