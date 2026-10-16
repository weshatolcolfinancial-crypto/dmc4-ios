#include "lzx_decompress.h"
#include "xmem_decompress.h"
#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <climits>
#include <zlib.h>

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

static int DecompressRawLzx(const void *src, size_t srcLen, void *dst, size_t dstLen,
                            uint32_t windowSize, int resetInterval, bool noIntelHeader) {
    if (!src || !dst || srcLen == 0 || dstLen == 0) return -1;

    uint32_t windowBits = 0;
    while ((1u << windowBits) < windowSize && windowBits < 32) {
        windowBits++;
    }
    if (windowBits < 15) windowBits = 15;
    if (windowBits > 21) windowBits = 21;

    mspack_system *sys = mspack_memory_sys_create();
    if (!sys) return -1;

    mspack_memory_file *lzxsrc = mspack_memory_open(sys, const_cast<void *>(src), srcLen);
    mspack_memory_file *lzxdst = mspack_memory_open(sys, dst, dstLen);
    lzxd_stream *lzxd = lzxd_init(sys, (mspack_file *)lzxsrc, (mspack_file *)lzxdst,
                                  windowBits, resetInterval, 0x8000, (off_t)dstLen, 0);

    int resultCode = -1;
    if (lzxd) {
        if (noIntelHeader) {
            lzxd->no_intel_header = 1;
            lzxd->header_read = 1;
            lzxd->intel_filesize = 0;
            lzxd->intel_started = 0;
        }
        resultCode = lzxd_decompress(lzxd, (off_t)dstLen);
        lzxd_free(lzxd);
    }

    if (lzxsrc) mspack_memory_close(lzxsrc);
    if (lzxdst) mspack_memory_close(lzxdst);
    if (sys) mspack_memory_sys_destroy(sys);

    return (resultCode == MSPACK_ERR_OK) ? 0 : -1;
}

static int DecompressRawDeflate(const void *src, size_t srcLen, void *dst, size_t dstLen, int windowBits) {
    if (!src || !dst || srcLen == 0 || dstLen == 0) return -1;
    z_stream strm;
    std::memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef*)src;
    strm.avail_in = (uInt)srcLen;
    strm.next_out = (Bytef*)dst;
    strm.avail_out = (uInt)dstLen;

    int ret = inflateInit2(&strm, windowBits);
    if (ret != Z_OK) return -1;

    ret = inflate(&strm, Z_FINISH);
    inflateEnd(&strm);

    if (ret == Z_STREAM_END || (ret == Z_OK && strm.avail_out == 0)) {
        return 0;
    }
    return -1;
}

static inline uint32_t ReadBe32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static inline uint32_t ReadLe32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static int DecompressXCompressContainer(const uint8_t *src, size_t srcLen, uint8_t *dst, size_t dstLen) {
    if (srcLen < 24 || dstLen == 0) return -1;

    uint32_t magicBe = ReadBe32(src);
    uint32_t magicLe = ReadLe32(src);
    bool isContainer = false;
    bool swapBytes = false;

    if (magicBe == 0x0FF512EE || magicBe == 0x0FF512ED) {
        isContainer = true;
        swapBytes = false;
    } else if (magicLe == 0x0FF512EE || magicLe == 0x0FF512ED) {
        isContainer = true;
        swapBytes = true;
    }

    if (!isContainer) return -1;

    uint32_t windowSize = swapBytes ? ReadLe32(src + 12) : ReadBe32(src + 12);
    uint32_t partitionSize = swapBytes ? ReadLe32(src + 16) : ReadBe32(src + 16);
    if (windowSize < 0x8000) windowSize = 0x8000;
    if (partitionSize == 0 || partitionSize > 0x80000) partitionSize = 0x80000;

    size_t inPos = 24;
    size_t outPos = 0;

    while (inPos + 4 <= srcLen && outPos < dstLen) {
        uint32_t blockSize = swapBytes ? ReadLe32(src + inPos) : ReadBe32(src + inPos);
        inPos += 4;
        if (blockSize == 0 || inPos + blockSize > srcLen) break;

        size_t chunkOut = std::min((size_t)partitionSize, dstLen - outPos);
        int err = DecompressRawLzx(src + inPos, blockSize, dst + outPos, chunkOut, windowSize, 1, true);
        if (err != 0) {
            if (blockSize == chunkOut) {
                std::memcpy(dst + outPos, src + inPos, chunkOut);
            } else {
                return -1;
            }
        }
        outPos += chunkOut;
        inPos += blockSize;
    }

    return (outPos == dstLen) ? 0 : -1;
}

int Decompress(const void *src, size_t srcLen, void *dst, size_t dstLen,
               const char **outMethod, uint32_t windowSize) {
    if (!src || !dst || srcLen == 0 || dstLen == 0) return -1;
    const uint8_t *bytes = (const uint8_t *)src;

    // 1. Check for XCompress Native Container (0x0FF512EE / 0x0FF512ED)
    if (DecompressXCompressContainer(bytes, srcLen, (uint8_t*)dst, dstLen) == 0) {
        if (outMethod) *outMethod = "XCompressContainer";
        return 0;
    }

    // 2. Raw Deflate (-15): Headerless deflate stream used in Capcom MT Framework ARC
    if (DecompressRawDeflate(bytes, srcLen, dst, dstLen, -15) == 0) {
        if (outMethod) *outMethod = "RawDeflate";
        return 0;
    }

    // 3. Standard Zlib (15): With 0x78 zlib header
    if (DecompressRawDeflate(bytes, srcLen, dst, dstLen, 15) == 0) {
        if (outMethod) *outMethod = "Zlib";
        return 0;
    }

    // 4. Auto zlib / gzip (47)
    if (DecompressRawDeflate(bytes, srcLen, dst, dstLen, 47) == 0) {
        if (outMethod) *outMethod = "Gzip";
        return 0;
    }

    // 5. Raw XMem LZX without Intel E8 header (32KB window = 0x8000, continuous stream)
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x8000, 0, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_32k";
        return 0;
    }

    // 6. Raw XMem LZX with 32KB partition reset (resetInterval = 1)
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x8000, 1, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_32k_Reset1";
        return 0;
    }

    // 7. Raw XMem LZX with 64KB, 128KB, 256KB, 512KB windows
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x10000, 0, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_64k";
        return 0;
    }
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x20000, 0, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_128k";
        return 0;
    }
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x40000, 8, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_256k_P8";
        return 0;
    }
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x80000, 16, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_512k_P16";
        return 0;
    }

    // 8. Xbox 360 XMem frame-chunked (XNB style 2-byte chunk headers)
    if (dmc4::xmem::Decompress(bytes, srcLen, (uint8_t*)dst, dstLen) == 0) {
        if (outMethod) *outMethod = "XMemChunked";
        return 0;
    }

    // 9. Standard CAB LZX (with Intel E8 header)
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x8000, 0, false) == 0) {
        if (outMethod) *outMethod = "CABLzx_32k";
        return 0;
    }
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x20000, 0, false) == 0) {
        if (outMethod) *outMethod = "CABLzx_128k";
        return 0;
    }

    return -1;
}

} // namespace lzx
} // namespace dmc4
