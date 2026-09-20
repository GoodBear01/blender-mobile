#!/usr/bin/env python3
"""Write a 1024x1024 PNG app icon (orange ring on black) without Pillow."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


def png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path: Path, size: int = 1024) -> None:
    raw = bytearray()
    cx = cy = size / 2.0
    outer = size * 0.38
    inner = size * 0.22
    for y in range(size):
        raw.append(0)
        for x in range(size):
            dx = x - cx
            dy = y - cy
            d = (dx * dx + dy * dy) ** 0.5
            if inner <= d <= outer:
                raw.extend((235, 115, 18, 255))
            elif d < inner:
                raw.extend((18, 18, 18, 255))
            else:
                raw.extend((0, 0, 0, 255))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + png_chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


if __name__ == "__main__":
    dest = Path(__file__).resolve().parents[1] / "BlenderMobile" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    write_png(dest)
    print(dest)
