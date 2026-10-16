#include "lzx_decompress.h"
#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <climits>

#if __has_include(<zlib.h>)
#include <zlib.h>
#else
extern "C" {
    typedef unsigned long uLongf;
    typedef unsigned char Bytef;
    typedef unsigned int uInt;
    typedef struct z_stream_s {
        Bytef    *next_in;
        uInt     avail_in;
        uLongf   total_in;
        Bytef    *next_out;
        uInt     avail_out;
        uLongf   total_out;
        char     *msg;
        struct internal_state *state;
        void*    (*zalloc)(void*, uInt, uInt);
        void     (*zfree)(void*, void*);
        void*    opaque;
        int      data_type;
        uLongf   adler;
        uLongf   reserved;
    } z_stream;
    #define Z_OK            0
    #define Z_STREAM_END    1
    #define Z_FINISH        4
    int inflateInit2_(z_stream *strm, int windowBits, const char *version, int stream_size);
    #define inflateInit2(strm, windowBits) \
            inflateInit2_((strm), (windowBits), "1.2.11", (int)sizeof(z_stream))
    int inflate(z_stream *strm, int flush);
    int inflateEnd(z_stream *strm);
}
#endif

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

struct ChunkedInput {
    const uint8_t *src;
    size_t srcLen;
    size_t srcPos;
    size_t chunkRemaining;

    ChunkedInput(const uint8_t *s, size_t len)
        : src(s), srcLen(len), srcPos(0), chunkRemaining(0) {}
};

static int mspack_chunked_read(mspack_file *file, void *buffer, int chars) {
    auto memfile = (mspack_memory_file *)file;
    auto chunked = (ChunkedInput *)memfile->buffer;
    uint8_t *out = (uint8_t *)buffer;
    int bytesRead = 0;

    while (bytesRead < chars && chunked->srcPos < chunked->srcLen) {
        if (chunked->chunkRemaining == 0) {
            if (chunked->src[chunked->srcPos] == 0xFF) {
                if (chunked->srcPos + 5 > chunked->srcLen) break;
                uint32_t us = ((uint32_t)chunked->src[chunked->srcPos + 1] << 8) | chunked->src[chunked->srcPos + 2];
                uint32_t cs = ((uint32_t)chunked->src[chunked->srcPos + 3] << 8) | chunked->src[chunked->srcPos + 4];
                chunked->srcPos += 5;
                chunked->chunkRemaining = cs;
            } else {
                if (chunked->srcPos + 2 > chunked->srcLen) break;
                uint32_t cs = ((uint32_t)chunked->src[chunked->srcPos] << 8) | chunked->src[chunked->srcPos + 1];
                chunked->srcPos += 2;
                chunked->chunkRemaining = cs;
            }
            if (chunked->chunkRemaining == 0) break;
        }

        size_t toRead = std::min((size_t)(chars - bytesRead), chunked->chunkRemaining);
        if (chunked->srcPos + toRead > chunked->srcLen) toRead = chunked->srcLen - chunked->srcPos;
        if (toRead == 0) break;

        std::memcpy(out + bytesRead, chunked->src + chunked->srcPos, toRead);
        chunked->srcPos += toRead;
        chunked->chunkRemaining -= toRead;
        bytesRead += (int)toRead;
    }

    return bytesRead;
}

static int DecompressChunkedLzx(const uint8_t *src, size_t srcLen, uint8_t *dst, size_t dstLen,
                                uint32_t windowSize, int resetInterval) {
    if (!src || !dst || srcLen == 0 || dstLen == 0) return -1;

    // Verify chunk 0 header bounds
    if (src[0] == 0xFF) {
        if (srcLen < 5) return -1;
        uint32_t cs = ((uint32_t)src[3] << 8) | src[4];
        if (cs == 0 || cs + 5 > srcLen) return -1;
    } else {
        if (srcLen < 2) return -1;
        uint32_t cs = ((uint32_t)src[0] << 8) | src[1];
        if (cs == 0 || cs + 2 > srcLen) return -1;
    }

    uint32_t windowBits = 0;
    while ((1u << windowBits) < windowSize && windowBits < 32) {
        windowBits++;
    }
    if (windowBits < 15) windowBits = 15;
    if (windowBits > 21) windowBits = 21;

    ChunkedInput chunked(src, srcLen);

    mspack_system *sys = (mspack_system *)std::calloc(1, sizeof(mspack_system));
    if (!sys) return -1;
    sys->read = mspack_chunked_read;
    sys->write = mspack_memory_write;
    sys->alloc = mspack_memory_alloc;
    sys->free = mspack_memory_free;
    sys->copy = mspack_memory_copy;

    mspack_memory_file *lzxsrc = (mspack_memory_file *)std::calloc(1, sizeof(mspack_memory_file));
    if (!lzxsrc) { std::free(sys); return -1; }
    lzxsrc->buffer = &chunked;
    lzxsrc->buffer_size = (off_t)srcLen;

    mspack_memory_file *lzxdst = mspack_memory_open(sys, dst, dstLen);
    if (!lzxdst) { std::free(lzxsrc); std::free(sys); return -1; }

    lzxd_stream *lzxd = lzxd_init(sys, (mspack_file *)lzxsrc, (mspack_file *)lzxdst,
                                  windowBits, resetInterval, 0x8000, (off_t)dstLen, 0);

    int resultCode = -1;
    if (lzxd) {
        lzxd->no_intel_header = 1;
        lzxd->header_read = 1;
        lzxd->intel_filesize = 0;
        lzxd->intel_started = 0;

        resultCode = lzxd_decompress(lzxd, (off_t)dstLen);
        lzxd_free(lzxd);
    }

    std::free(lzxsrc);
    mspack_memory_close(lzxdst);
    std::free(sys);

    return (resultCode == MSPACK_ERR_OK) ? 0 : -1;
}

static int DecompressChunkByChunk(const uint8_t *src, size_t srcLen, uint8_t *dst, size_t dstLen,
                                  uint32_t windowSize) {
    if (!src || !dst || srcLen == 0 || dstLen == 0) return -1;

    size_t inPos = 0;
    size_t outPos = 0;

    while (inPos < srcLen && outPos < dstLen) {
        uint32_t us = 0, cs = 0;
        if (src[inPos] == 0xFF) {
            if (inPos + 5 > srcLen) break;
            us = ((uint32_t)src[inPos + 1] << 8) | src[inPos + 2];
            cs = ((uint32_t)src[inPos + 3] << 8) | src[inPos + 4];
            inPos += 5;
        } else {
            if (inPos + 2 > srcLen) break;
            us = 32768;
            cs = ((uint32_t)src[inPos] << 8) | src[inPos + 1];
            inPos += 2;
        }
        if (cs == 0 || inPos + cs > srcLen) break;

        size_t curOut = std::min((size_t)us, dstLen - outPos);

        // 1. If chunk is stored uncompressed
        if (cs == curOut) {
            std::memcpy(dst + outPos, src + inPos, curOut);
            outPos += curOut;
            inPos += cs;
            continue;
        }

        // 2. Try raw LZX for this chunk
        int err = DecompressRawLzx(src + inPos, cs, dst + outPos, curOut, windowSize, 0, true);
        if (err != 0) {
            // 3. Try raw deflate for this chunk
            err = DecompressRawDeflate(src + inPos, cs, dst + outPos, curOut, -15);
        }
        if (err != 0) {
            return -1;
        }

        outPos += curOut;
        inPos += cs;
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

    // 2. Streaming Chunked LZX through libmspack (continuous sliding history, 32KB window)
    if (DecompressChunkedLzx(bytes, srcLen, (uint8_t*)dst, dstLen, 0x8000, 0) == 0) {
        if (outMethod) *outMethod = "XMemChunked_LZX32k_Continuous";
        return 0;
    }

    // 3. Streaming Chunked LZX through libmspack (32KB frame reset)
    if (DecompressChunkedLzx(bytes, srcLen, (uint8_t*)dst, dstLen, 0x8000, 1) == 0) {
        if (outMethod) *outMethod = "XMemChunked_LZX32k_Reset1";
        return 0;
    }

    // 4. Streaming Chunked LZX with larger 64KB/128KB windows
    if (DecompressChunkedLzx(bytes, srcLen, (uint8_t*)dst, dstLen, 0x10000, 0) == 0) {
        if (outMethod) *outMethod = "XMemChunked_LZX64k";
        return 0;
    }
    if (DecompressChunkedLzx(bytes, srcLen, (uint8_t*)dst, dstLen, 0x20000, 0) == 0) {
        if (outMethod) *outMethod = "XMemChunked_LZX128k";
        return 0;
    }

    // 5. Independent chunk-by-chunk LZX/Deflate
    if (DecompressChunkByChunk(bytes, srcLen, (uint8_t*)dst, dstLen, 0x8000) == 0) {
        if (outMethod) *outMethod = "XMemChunkByChunk";
        return 0;
    }

    // 6. Headerless Raw Deflate (-15)
    if (DecompressRawDeflate(bytes, srcLen, dst, dstLen, -15) == 0) {
        if (outMethod) *outMethod = "RawDeflate";
        return 0;
    }

    // 7. Standard Zlib (15, 0x78 header)
    if (DecompressRawDeflate(bytes, srcLen, dst, dstLen, 15) == 0) {
        if (outMethod) *outMethod = "Zlib";
        return 0;
    }

    // 8. Raw continuous LZX without chunk headers (window 32KB..128KB)
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x8000, 0, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_32k";
        return 0;
    }
    if (DecompressRawLzx(bytes, srcLen, dst, dstLen, 0x20000, 0, true) == 0) {
        if (outMethod) *outMethod = "RawLZX_128k";
        return 0;
    }

    return -1;
}

} // namespace lzx
} // namespace dmc4
