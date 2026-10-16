#!/usr/bin/env python3
"""
Full Xbox 360 GDFX ISO Extractor for Devil May Cry 4.
Extracts default.xex and Capcom MT Framework assets directly from an Xbox 360 ISO image.

Usage:
    python tools/extract_iso.py path/to/DevilMayCry4.iso -o game/
    python tools/extract_iso.py path/to/DevilMayCry4.iso --solo-xex -o game/
"""

import sys
import os
import struct
import argparse

GDFX_MAGIC = b"MICROSOFT*XBOX*MEDIA"
SECTOR_SIZE = 2048

def find_gdfx_offset(f, file_size):
    # Standard XGD offsets
    probe_offsets = [0xFD90000, 0x0, 0x10000, 0x2080000]
    for off in probe_offsets:
        if off < file_size:
            f.seek(off)
            if f.read(20) == GDFX_MAGIC:
                return off

    print("[*] Scanning first 300MB for GDFX partition magic...")
    f.seek(0)
    chunk_size = 16 * 1024 * 1024
    pos = 0
    while pos < min(file_size, 300 * 1024 * 1024):
        f.seek(pos)
        data = f.read(chunk_size)
        idx = data.find(GDFX_MAGIC)
        if idx != -1:
            return pos + idx
        pos += chunk_size - 32
    return -1

def parse_and_extract_dir(f, base_offset, sector, size, current_dir, solo_xex=False):
    if size == 0 or size > 16 * 1024 * 1024:
        return

    os.makedirs(current_dir, exist_ok=True)
    f.seek(base_offset + sector * SECTOR_SIZE)
    dir_data = f.read(size)

    stack = [0]
    visited = set()

    while stack:
        entry_idx = stack.pop()
        byte_off = entry_idx * 4
        if byte_off + 14 > size or entry_idx in visited:
            continue
        visited.add(entry_idx)

        left, right, sec, fsize, attrs, name_len = struct.unpack_from("<HHIIBB", dir_data, byte_off)
        if name_len == 0 or byte_off + 14 + name_len > size:
            continue

        name = dir_data[byte_off + 14 : byte_off + 14 + name_len].decode("latin1", errors="replace")
        target_path = os.path.join(current_dir, name)
        is_dir = (attrs & 0x10) != 0

        if is_dir:
            if not solo_xex:
                parse_and_extract_dir(f, base_offset, sec, fsize, target_path, solo_xex)
        else:
            if solo_xex and name.lower() != "default.xex":
                pass
            else:
                print(f"[+] Extracting: {name} ({fsize / (1024*1024):.2f} MB)...")
                f.seek(base_offset + sec * SECTOR_SIZE)
                with open(target_path, "wb") as out_f:
                    remaining = fsize
                    buf_size = 2 * 1024 * 1024
                    while remaining > 0:
                        chunk = f.read(min(remaining, buf_size))
                        if not chunk:
                            break
                        out_f.write(chunk)
                        remaining -= len(chunk)

        if left != 0 and left != 0xFFFF:
            stack.append(left)
        if right != 0 and right != 0xFFFF:
            stack.append(right)

def extract_iso(iso_path, output_dir, solo_xex=False):
    if not os.path.isfile(iso_path):
        print(f"[-] Error: ISO file not found at '{iso_path}'")
        return False

    file_size = os.path.getsize(iso_path)
    print(f"[*] Opening ISO: {iso_path} ({file_size / (1024*1024*1024):.2f} GB)")

    with open(iso_path, "rb") as f:
        base_offset = find_gdfx_offset(f, file_size)
        if base_offset == -1:
            print("[-] Error: No GDFX partition found in ISO.")
            return False

        print(f"[+] Found GDFX partition at offset: 0x{base_offset:X}")
        f.seek(base_offset + 0x14)
        root_sector, root_size = struct.unpack("<II", f.read(8))
        print(f"[+] Root Directory: Sector 0x{root_sector:X}, Size: {root_size} bytes")

        os.makedirs(output_dir, exist_ok=True)
        parse_and_extract_dir(f, base_offset, root_sector, root_size, output_dir, solo_xex)
        print(f"\n[✓] Extraction finished! Game assets saved to: {output_dir}")
        return True

def main():
    parser = argparse.ArgumentParser(description="Extract DMC4 Xbox 360 ISO")
    parser.add_argument("iso", help="Path to Devil May Cry 4 Xbox 360 ISO")
    parser.add_argument("-o", "--output", default="game", help="Output directory (default: game)")
    parser.add_argument("--solo-xex", action="store_true", help="Extract only default.xex")
    args = parser.parse_args()

    extract_iso(args.iso, args.output, args.solo_xex)

if __name__ == "__main__":
    main()
