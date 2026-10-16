#include "xmem_decompress.h"
#include <vector>
#include <cstring>
#include <algorithm>

namespace dmc4 {
namespace xmem {

static constexpr int LZX_MIN_MATCH = 2;
static constexpr int LZX_NUM_CHARS = 256;
static constexpr int LZX_NUM_SECONDARY_LENGTHS = 249;
static constexpr int LZX_BLOCKTYPE_VERBATIM = 1;
static constexpr int LZX_BLOCKTYPE_ALIGNED = 2;
static constexpr int LZX_BLOCKTYPE_UNCOMPRESSED = 3;
static constexpr int LZX_LEAF_MARKER = 0x7FFFFFFF;
static constexpr int LZX_MAX_NODES = 4096;
static constexpr uint32_t XMEM_WINDOW_SIZE = 0x20000; // 128KB default window

static const uint8_t EXTRA_BITS[52] = {
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10,
    11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17
};

static const uint32_t POSITION_BASE[52] = {
    0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512,
    768, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384, 24576, 32768,
    49152, 65536, 98304, 131072, 196608, 262144, 393216, 524288, 655360, 786432,
    917504, 1048576, 1179648, 1310720, 1441792, 1572864, 1703936, 1835008,
    1966080, 2097152, 2228224
};

struct BitReader {
    const uint8_t *data;
    size_t sz;
    size_t pos;
    uint64_t buf;
    int bl;

    BitReader(const uint8_t *d, size_t offset, size_t size)
        : data(d), sz(offset + size), pos(offset), buf(0), bl(0) {}

    uint32_t read(int n) {
        if (n == 0) return 0;
        while (bl < n) {
            if (pos + 1 < sz) {
                uint32_t w = (uint32_t)data[pos] | ((uint32_t)data[pos + 1] << 8);
                pos += 2;
                buf = (buf << 16) | w;
                bl += 16;
            } else if (pos < sz) {
                buf = (buf << 8) | data[pos];
                pos += 1;
                bl += 8;
            } else {
                break;
            }
        }
        uint32_t v = (uint32_t)((buf >> (bl - n)) & ((1ULL << n) - 1));
        bl -= n;
        buf &= (1ULL << bl) - 1;
        return v;
    }
};

struct HuffmanNode {
    int child0;
    int child1;
};

struct HuffmanTree {
    std::vector<HuffmanNode> nodes;
    bool isValid;

    HuffmanTree() : isValid(false) {}

    static HuffmanTree build(const int *lens, int num_symbols) {
        HuffmanTree ht;
        ht.nodes.push_back({0, 0});

        int counts[17] = {0};
        int starts[17] = {0};

        for (int i = 0; i < num_symbols; ++i) {
            if (lens[i] > 0 && lens[i] <= 16) {
                counts[lens[i]]++;
            }
        }

        starts[1] = 0;
        for (int i = 1; i < 16; ++i) {
            starts[i + 1] = (starts[i] + counts[i]) << 1;
        }

        for (int sym = 0; sym < num_symbols; ++sym) {
            int length = lens[sym];
            if (length <= 0 || length > 16) continue;
            int code = starts[length]++;
            if (code >= (1 << length)) {
                ht.isValid = false;
                return ht;
            }

            int node = 0;
            for (int i = length - 1; i >= 0; --i) {
                int bit = (code >> i) & 1;
                if (i == 0) {
                    if (ht.nodes.size() >= LZX_MAX_NODES) {
                        ht.isValid = false;
                        return ht;
                    }
                    int leaf_idx = (int)ht.nodes.size();
                    ht.nodes.push_back({sym, LZX_LEAF_MARKER});
                    if (bit == 0) ht.nodes[node].child0 = leaf_idx;
                    else ht.nodes[node].child1 = leaf_idx;
                } else {
                    int child = (bit == 0) ? ht.nodes[node].child0 : ht.nodes[node].child1;
                    if (child == 0) {
                        if (ht.nodes.size() >= LZX_MAX_NODES) {
                            ht.isValid = false;
                            return ht;
                        }
                        child = (int)ht.nodes.size();
                        ht.nodes.push_back({0, 0});
                        if (bit == 0) ht.nodes[node].child0 = child;
                        else ht.nodes[node].child1 = child;
                    }
                    node = child;
                }
            }
        }
        ht.isValid = true;
        return ht;
    }

    int decode(BitReader &br) const {
        if (!isValid || nodes.empty()) return -1;
        int node = 0;
        for (int i = 0; i < 32; ++i) {
            int bit = br.read(1);
            if (node >= (int)nodes.size()) return -1;
            int child = (bit == 0) ? nodes[node].child0 : nodes[node].child1;
            if (child == 0 || child >= (int)nodes.size()) return -1;
            if (nodes[child].child1 == LZX_LEAF_MARKER) {
                return nodes[child].child0;
            }
            node = child;
        }
        return -1;
    }
};

static bool ReadLengths(BitReader &br, int *lens, int first, int last) {
    int pt_lens[20];
    for (int i = 0; i < 20; ++i) {
        pt_lens[i] = br.read(4);
    }
    HuffmanTree pt_tree = HuffmanTree::build(pt_lens, 20);
    if (!pt_tree.isValid) return false;

    int x = first;
    while (x < last) {
        int z = pt_tree.decode(br);
        if (z < 0) return false;
        if (z == 17) {
            int run = br.read(4) + 4;
            for (int r = 0; r < run && x < last; ++r) {
                lens[x++] = 0;
            }
        } else if (z == 18) {
            int run = br.read(5) + 20;
            for (int r = 0; r < run && x < last; ++r) {
                lens[x++] = 0;
            }
        } else if (z == 19) {
            int run = br.read(1) + 4;
            int delta = pt_tree.decode(br);
            if (delta < 0) return false;
            int d = (lens[x] - delta) % 17;
            if (d < 0) d += 17;
            for (int r = 0; r < run && x < last; ++r) {
                lens[x++] = d;
            }
        } else {
            int d = (lens[x] - z) % 17;
            if (d < 0) d += 17;
            lens[x++] = d;
        }
    }
    return true;
}

static void ApplyE8(uint8_t *data, size_t offset, size_t size, uint32_t filesize) {
    if (size <= 10) return;
    size_t end = size - 10;
    size_t i = 0;
    while (i < end) {
        if (data[offset + i] == 0xE8) {
            uint32_t abs_off = (uint32_t)data[offset + i + 1] |
                               ((uint32_t)data[offset + i + 2] << 8) |
                               ((uint32_t)data[offset + i + 3] << 16) |
                               ((uint32_t)data[offset + i + 4] << 24);
            uint32_t rel_off;
            if (abs_off < filesize) {
                rel_off = abs_off - (uint32_t)(offset + i);
            } else if (abs_off >= 0x80000000 && abs_off < 0x80000000 + filesize) {
                rel_off = abs_off + filesize;
            } else {
                i++;
                continue;
            }
            data[offset + i + 1] = (uint8_t)(rel_off & 0xFF);
            data[offset + i + 2] = (uint8_t)((rel_off >> 8) & 0xFF);
            data[offset + i + 3] = (uint8_t)((rel_off >> 16) & 0xFF);
            data[offset + i + 4] = (uint8_t)((rel_off >> 24) & 0xFF);
            i += 5;
        } else {
            i++;
        }
    }
}

struct LzxState {
    uint32_t win_sz;
    uint32_t wmask;
    std::vector<uint8_t> window;
    int num_off;
    int R0, R1, R2;
    int block_rem, block_type, block_len;
    int header_read;
    uint32_t win_pos;
    uint32_t intel_filesize;
    int intel_active;
    size_t intel_offset;
    int MT_len[720];
    int LEN_len[320];
    int AL_len[12];
    HuffmanTree mt_tree;
    HuffmanTree lt_tree;
    HuffmanTree al_tree;
    bool LEN_empty;

    uint8_t *out;
    size_t out_pos;
    size_t out_sz;

    LzxState(uint32_t window_size)
        : win_sz(window_size), wmask(window_size - 1), window(window_size, 0),
          num_off(34), R0(1), R1(1), R2(1), block_rem(0), block_type(0), block_len(0),
          header_read(0), win_pos(0), intel_filesize(0x00FFFFFF), intel_active(0),
          intel_offset(0), LEN_empty(true), out(nullptr), out_pos(0), out_sz(0) {
        std::memset(MT_len, 0, sizeof(MT_len));
        std::memset(LEN_len, 0, sizeof(LEN_len));
        std::memset(AL_len, 0, sizeof(AL_len));
    }
};

static int DecodeFrame(LzxState &st, BitReader &br, uint32_t uncomp_sz) {
    int R0 = st.R0, R1 = st.R1, R2 = st.R2;
    uint32_t wp = st.win_pos;
    uint32_t wm = st.wmask;
    uint8_t *window = st.window.data();
    uint8_t *out = st.out;
    size_t frame_start = st.out_pos;
    size_t target = std::min(st.out_pos + (size_t)uncomp_sz, st.out_sz);

    if (st.header_read) {
        if (br.read(1)) {
            uint32_t hi = br.read(16);
            uint32_t lo = br.read(16);
            st.intel_filesize = (hi << 16) | lo;
            st.intel_active = 1;
        }
        st.header_read = 0;
    }

    while (st.out_pos < target) {
        if (st.block_rem == 0) {
            st.block_type = br.read(3);
            st.block_rem = st.block_len = br.read(24);
            if (st.block_type < 1 || st.block_type > 3) return -1;

            if (st.block_type == LZX_BLOCKTYPE_ALIGNED) {
                for (int i = 0; i < 8; ++i) st.AL_len[i] = br.read(3);
                st.al_tree = HuffmanTree::build(st.AL_len, 8);
                if (!st.al_tree.isValid) return -1;

                if (!ReadLengths(br, st.MT_len, 0, 256)) return -1;
                if (!ReadLengths(br, st.MT_len, 256, 256 + st.num_off * 8)) return -1;
                st.mt_tree = HuffmanTree::build(st.MT_len, 256 + st.num_off * 8);
                if (!st.mt_tree.isValid) return -1;

                if (!ReadLengths(br, st.LEN_len, 0, LZX_NUM_SECONDARY_LENGTHS)) return -1;
                st.lt_tree = HuffmanTree::build(st.LEN_len, LZX_NUM_SECONDARY_LENGTHS);
                st.LEN_empty = !st.lt_tree.isValid;
            } else if (st.block_type == LZX_BLOCKTYPE_VERBATIM) {
                if (!ReadLengths(br, st.MT_len, 0, 256)) return -1;
                if (!ReadLengths(br, st.MT_len, 256, 256 + st.num_off * 8)) return -1;
                st.mt_tree = HuffmanTree::build(st.MT_len, 256 + st.num_off * 8);
                if (!st.mt_tree.isValid) return -1;

                if (!ReadLengths(br, st.LEN_len, 0, LZX_NUM_SECONDARY_LENGTHS)) return -1;
                st.lt_tree = HuffmanTree::build(st.LEN_len, LZX_NUM_SECONDARY_LENGTHS);
                st.LEN_empty = !st.lt_tree.isValid;

                std::memset(st.AL_len, 0, sizeof(st.AL_len));
                st.al_tree = HuffmanTree::build(st.AL_len, 8);
            } else if (st.block_type == LZX_BLOCKTYPE_UNCOMPRESSED) {
                if (br.bl & 15) br.read(br.bl & 15);
                R0 = br.read(16) | (br.read(16) << 16);
                R1 = br.read(16) | (br.read(16) << 16);
                R2 = br.read(16) | (br.read(16) << 16);
            }
        }

        if (st.block_type == LZX_BLOCKTYPE_UNCOMPRESSED) {
            uint8_t c = 0;
            if (br.bl == 16) {
                c = (uint8_t)(br.buf & 0xFF);
                br.buf >>= 8;
                br.bl -= 8;
            } else if (br.bl == 8) {
                c = (uint8_t)(br.buf & 0xFF);
                br.buf = 0;
                br.bl = 0;
            } else {
                if (br.pos >= br.sz) return -1;
                c = br.data[br.pos++];
            }
            window[wp] = c;
            wp = (wp + 1) & wm;
            out[st.out_pos++] = c;
            st.block_rem--;
            if (st.block_rem == 0) {
                if (br.bl & 15) {
                    br.bl = 0;
                    br.buf = 0;
                }
                if (br.pos & 1) br.pos++;
            }
        } else {
            int me = st.mt_tree.decode(br);
            if (me < 0) return -1;
            if (me < LZX_NUM_CHARS) {
                window[wp] = (uint8_t)me;
                wp = (wp + 1) & wm;
                out[st.out_pos++] = (uint8_t)me;
                st.block_rem--;
            } else {
                me -= LZX_NUM_CHARS;
                int ml = me & 7;
                if (ml == 7) {
                    if (st.LEN_empty) return -1;
                    int ex = st.lt_tree.decode(br);
                    if (ex < 0) return -1;
                    ml += ex;
                }
                ml += LZX_MIN_MATCH;

                int slot = me >> 3;
                int mo = 0;
                if (slot == 0) {
                    mo = R0;
                } else if (slot == 1) {
                    mo = R1;
                    R1 = R0;
                    R0 = mo;
                } else if (slot == 2) {
                    mo = R2;
                    R2 = R0;
                    R0 = mo;
                } else {
                    int ex_bits = (slot >= 50) ? 17 : (int)EXTRA_BITS[slot];
                    mo = (int)POSITION_BASE[slot] - 2;
                    if (ex_bits >= 3 && st.block_type == LZX_BLOCKTYPE_ALIGNED) {
                        if (ex_bits > 3) {
                            mo += br.read(ex_bits - 3) << 3;
                        }
                        int aligned_sym = st.al_tree.decode(br);
                        if (aligned_sym < 0) return -1;
                        mo += aligned_sym;
                    } else if (ex_bits > 0) {
                        mo += br.read(ex_bits);
                    }
                    R2 = R1;
                    R1 = R0;
                    R0 = mo;
                }

                while (ml > 0 && st.out_pos < target) {
                    uint8_t c = window[(wp - mo) & wm];
                    window[wp] = c;
                    wp = (wp + 1) & wm;
                    out[st.out_pos++] = c;
                    st.block_rem--;
                    ml--;
                }
            }
        }
    }

    if (st.intel_active && st.out_pos > frame_start) {
        ApplyE8(out, frame_start, st.out_pos - frame_start, st.intel_filesize);
    }

    st.intel_offset += st.out_pos - frame_start;
    st.win_pos = wp;
    st.R0 = R0;
    st.R1 = R1;
    st.R2 = R2;
    return 0;
}

int Decompress(const uint8_t *data, size_t compSize, uint8_t *out, size_t decompSize) {
    if (!data || !out || compSize == 0 || decompSize == 0) return -1;

    LzxState st(XMEM_WINDOW_SIZE);
    st.out = out;
    st.out_sz = decompSize;
    st.out_pos = 0;
    st.header_read = 1;
    st.intel_active = 0;
    st.intel_offset = 0;
    st.R0 = st.R1 = st.R2 = 1;

    size_t ip = 0;
    size_t end = compSize;

    while (ip < end && st.out_pos < st.out_sz) {
        uint32_t us = 0, cs = 0;
        if (data[ip] == 0xFF) {
            if (ip + 5 > end) break;
            us = ((uint32_t)data[ip + 1] << 8) | (uint32_t)data[ip + 2];
            cs = ((uint32_t)data[ip + 3] << 8) | (uint32_t)data[ip + 4];
            ip += 5;
        } else {
            if (ip + 2 > end) break;
            us = 32768;
            cs = ((uint32_t)data[ip] << 8) | (uint32_t)data[ip + 1];
            ip += 2;
        }
        if (cs == 0 || ip + cs > end) break;
        BitReader br(data, ip, cs);
        if (DecodeFrame(st, br, us) < 0) {
            return -1;
        }
        ip += cs;
    }
    return (st.out_pos == decompSize) ? 0 : -1;
}

} // namespace xmem
} // namespace dmc4
