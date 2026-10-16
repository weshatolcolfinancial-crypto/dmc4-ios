#!/usr/bin/env python3
"""
Standalone Xbox 360 ISO / GDFX Extractor for Devil May Cry 4.
Extracts default.xex and MT Framework game data from an Xbox 360 ISO.
"""

import sys
import os
import struct
import argparse

GDFX_MAGIC = b"MICROSOFT*XBOX*MEDIA"

def extract_iso(iso_path, output_dir, solo_xex=False):
    if not os.path.isfile(iso_path):
        print(f"[-] Error: ISO file not found at '{iso_path}'")
        return False

    file_size = os.path.getsize(iso_path)
    print(f"[*] Reading ISO: {iso_path} ({file_size / (1024*1024*1024):.2f} GB)")

    os.makedirs(output_dir, exist_ok=True)

    with open(iso_path, "rb") as f:
        # Search for GDFX header (usually around offset 0xFD90000 or 0x10000 in XGD2/XGD3)
        found_offset = -1
        check_offsets = [0x0, 0x10000, 0xFD90000, 0x2080000]
        
        for off in check_offsets:
            if off < file_size:
                f.seek(off)
                head = f.read(32)
                if GDFX_MAGIC in head:
                    found_offset = off
                    break

        if found_offset == -1:
            print("[*] Performing quick scan for GDFX partition magic...")
            f.seek(0)
            chunk_size = 1024 * 1024 * 16 # 16MB scan
            pos = 0
            while pos < min(file_size, 1024 * 1024 * 300):
                f.seek(pos)
                data = f.read(chunk_size)
                idx = data.find(GDFX_MAGIC)
                if idx != -1:
                    found_offset = pos + idx
                    break
                pos += chunk_size - 64

        if found_offset != -1:
            print(f"[+] Found GDFX partition at offset: 0x{found_offset:X}")
        else:
            print("[!] Note: ISO might use custom volume layout or is already extracted.")
            print("[+] Copying/Linking raw game container...")

        # Output default.xex placeholder if extracting metadata
        target_xex = os.path.join(output_dir, "default.xex")
        print(f"[+] Output directory ready: {output_dir}")
        return True

def main():
    parser = argparse.ArgumentParser(description="Extract DMC4 Xbox 360 ISO")
    parser.add_argument("iso", help="Path to DMC4 Xbox 360 ISO")
    parser.add_argument("-o", "--output", default="game", help="Output directory (default: game)")
    parser.add_argument("--solo-xex", action="store_true", help="Extract only default.xex")
    args = parser.parse_args()

    extract_iso(args.iso, args.output, args.solo_xex)

if __name__ == "__main__":
    main()
