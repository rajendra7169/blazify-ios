#!/usr/bin/env python3
"""
Enlarge the __LINKEDIT segment's vmsize so a code signature added later (by a
third-party signer like Sideloader/AltServer on Linux) still fits inside vmsize.

Why this exists: the modern linker sizes __LINKEDIT vmsize to just the
page-rounded filesize, leaving almost no slack. When a third-party signer
appends the signature, filesize grows past vmsize and iOS's dyld aborts the app
before main() with:

    segment '__LINKEDIT' filesize exceeds vmsize

Apple's own `codesign` bumps vmsize; the Linux signers don't. So we pre-inflate
it here, at build time, and every signed install launches cleanly.

Usage: fix_linkedit.py <path-to-macho-executable>
"""
import sys
import struct

PAGE = 0x4000  # 16 KiB, arm64 iOS page size


def round_up(n, a):
    return (n + a - 1) // a * a


def patch(path):
    data = bytearray(open(path, "rb").read())
    magic = struct.unpack("<I", data[:4])[0]
    if magic not in (0xFEEDFACF,):  # MH_MAGIC_64 little-endian
        print(f"  skip (not a thin arm64 Mach-O): {path}")
        return
    ncmds = struct.unpack("<I", data[16:20])[0]
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[off:off + 8])
        if cmd == 0x19:  # LC_SEGMENT_64
            seg = data[off + 8:off + 24].split(b"\x00")[0].decode()
            if seg == "__LINKEDIT":
                vmsize, _fileoff, filesize = struct.unpack("<QQQ", data[off + 32:off + 56])
                # Generous, size-proportional headroom for any signature.
                slack = max(0x40000, filesize // 50)
                new_vmsize = max(vmsize, round_up(filesize + slack, PAGE))
                if new_vmsize != vmsize:
                    struct.pack_into("<Q", data, off + 32, new_vmsize)
                    open(path, "wb").write(data)
                    print(f"  __LINKEDIT vmsize {vmsize} -> {new_vmsize} (filesize {filesize})")
                else:
                    print(f"  __LINKEDIT already roomy (vmsize {vmsize} >= filesize {filesize} + slack)")
                return
        off += size  # advance to the next load command — without this the loop never moves
    # Fail loudly: a silent miss here ships an IPA that dyld kills before main().
    sys.exit(f"  ERROR: __LINKEDIT segment not found in {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: fix_linkedit.py <macho>")
    patch(sys.argv[1])
