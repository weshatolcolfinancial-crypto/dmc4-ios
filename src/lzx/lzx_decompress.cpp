#include "lzx_decompress.h"
#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <climits>

#include "mspack.h"
#include "lzx.h"

typedef struct mspack_memory_file_t {
    mspack_system sys;
    void *buffer;
    off_t buffer_size;
    off_t offset;
} mspack_memory_file;

static mspack_memory_file *mspack_memory_open(mspack_system *sys, void *buffer, const size_t buffer_size) {
    if (buffer_size >= INT_MAX) return nullptr;
    auto memfile = (mspack_memory_file *)std::calloc(1, sizeof(mspack_memory_file));
    if (!memfile) return nullptr;
    memfile->buffer = buffer;
    memfile->buffer_size = (off_t)buffer_size;
    memfile->offset = 0;
    return memfile;
}

static void mspack_memory_close(mspack_memory_file *file) {
    std::free(file);
}

static int mspack_memory_read(mspack_file *file, void *buffer, int chars) {
    auto memfile = (mspack_memory_file *)file;
    const off_t remaining = memfile->buffer_size - memfile->offset;
    const off_t total = std::min(static_cast<off_t>(chars), remaining);
    std::memcpy(buffer, (uint8_t *)memfile->buffer + memfile->offset, total);
    memfile->offset += total;
    return (int)total;
}

static int mspack_memory_write(mspack_file *file, void *buffer, int chars) {
    auto memfile = (mspack_memory_file *)file;
    const off_t remaining = memfile->buffer_size - memfile->offset;
    const off_t total = std::min(static_cast<off_t>(chars), remaining);
    std::memcpy((uint8_t *)memfile->buffer + memfile->offset, buffer, total);
    memfile->offset += total;
    return (int)total;
}

static void *mspack_memory_alloc(mspack_system *sys, size_t chars) {
    return std::calloc(chars, 1);
}

static void mspack_memory_free(void *ptr) {
    std::free(ptr);
}

static void mspack_memory_copy(void *src, void *dest, size_t chars) {
    std::memcpy(dest, src, chars);
}

static mspack_system *mspack_memory_sys_create() {
    auto sys = (mspack_system *)std::calloc(1, sizeof(mspack_system));
    if (!sys) return nullptr;
    sys->read = mspack_memory_read;
    sys->write = mspack_memory_write;
    sys->alloc = mspack_memory_alloc;
    sys->free = mspack_memory_free;
    sys->copy = mspack_memory_copy;
    return sys;
}

static void mspack_memory_sys_destroy(struct mspack_system *sys) {
    std::free(sys);
}

namespace dmc4 {
namespace lzx {

static int DecompressInternal(const void *src, size_t srcLen, void *dst, size_t dstLen, uint32_t windowSize) {
    if (!src || !dst || srcLen == 0 || dstLen == 0) return -1;

    uint32_t windowBits = 0;
    while ((1u << windowBits) < windowSize && windowBits < 32) {
        windowBits++;
    }
    if (windowBits < 15 || windowBits > 21) {
        windowBits = 15; // default 32KB window (0x8000)
    }

    mspack_system *sys = mspack_memory_sys_create();
    if (!sys) return -1;

    mspack_memory_file *lzxsrc = mspack_memory_open(sys, const_cast<void *>(src), srcLen);
    mspack_memory_file *lzxdst = mspack_memory_open(sys, dst, dstLen);
    lzxd_stream *lzxd = lzxd_init(sys, (mspack_file *)lzxsrc, (mspack_file *)lzxdst,
                                  windowBits, 0, 0x8000, (off_t)dstLen, 0);

    int resultCode = -1;
    if (lzxd) {
        resultCode = lzxd_decompress(lzxd, (off_t)dstLen);
        lzxd_free(lzxd);
    }

    if (lzxsrc) mspack_memory_close(lzxsrc);
    if (lzxdst) mspack_memory_close(lzxdst);
    if (sys) mspack_memory_sys_destroy(sys);

    return resultCode; // 0 == MSPACK_ERR_OK
}

int Decompress(const void *src, size_t srcLen, void *dst, size_t dstLen, uint32_t windowSize) {
    int res = DecompressInternal(src, srcLen, dst, dstLen, windowSize);
    if (res == 0) return 0;

    // Fallback window sizes
    if (windowSize == 0x8000) {
        res = DecompressInternal(src, srcLen, dst, dstLen, 0x10000); // 64KB
        if (res == 0) return 0;
        res = DecompressInternal(src, srcLen, dst, dstLen, 0x20000); // 128KB
        if (res == 0) return 0;
    }
    return res;
}

} // namespace lzx
} // namespace dmc4
