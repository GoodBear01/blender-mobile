#!/usr/bin/env python3
"""Remove duplicate Mach-O load commands that make ld fail.

libblender already links /usr/lib/libz.1.dylib. BeeWare also records
@rpath/libz.1.dylib. Rewriting that path onto the system zlib makes ld
report "Duplicate linked dylib". Drop the extra zlib command instead.
"""
import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_LOAD_UPWARD_DYLIB = 0x80000023
LOAD_CMDS = {
    LC_LOAD_DYLIB,
    LC_LOAD_WEAK_DYLIB,
    LC_REEXPORT_DYLIB,
    LC_LOAD_UPWARD_DYLIB,
}


def dylib_name(blob: bytes) -> str:
    if len(blob) < 24:
        return ""
    name_off = struct.unpack_from("<I", blob, 8)[0]
    if name_off >= len(blob):
        return ""
    return blob[name_off:].split(b"\x00", 1)[0].decode("utf-8", "replace")


def extra_zlib(name: str, has_system_z: bool) -> bool:
    if not has_system_z or not name:
        return False
    if name == "/usr/lib/libz.1.dylib":
        return False
    base = name.rsplit("/", 1)[-1]
    return base == "libz.dylib" or base.startswith("libz.")


def rewrite_slice(data: bytearray, start: int) -> list[str]:
    magic = struct.unpack_from("<I", data, start)[0]
    if magic != MH_MAGIC_64:
        return []
    ncmds, sizeofcmds = struct.unpack_from("<II", data, start + 16)
    header = 32
    off = start + header
    end = off + sizeofcmds
    commands = []
    for _ in range(ncmds):
        if off + 8 > end:
            break
        _cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmdsize < 8 or off + cmdsize > len(data):
            break
        commands.append(bytes(data[off : off + cmdsize]))
        off += cmdsize
    names = []
    has_system_z = False
    for blob in commands:
        cmd = struct.unpack_from("<I", blob, 0)[0]
        name = dylib_name(blob) if cmd in LOAD_CMDS else ""
        names.append(name)
        if name == "/usr/lib/libz.1.dylib":
            has_system_z = True
    kept = []
    removed = []
    seen = set()
    for blob, name in zip(commands, names):
        cmd = struct.unpack_from("<I", blob, 0)[0]
        drop = False
        if cmd in LOAD_CMDS and name:
            if name in seen or extra_zlib(name, has_system_z):
                drop = True
            else:
                seen.add(name)
        if drop:
            removed.append(name)
        else:
            kept.append(blob)
    if not removed:
        return []
    new_cmds = b"".join(kept)
    if len(new_cmds) > sizeofcmds:
        raise SystemExit(f"load commands grew in slice at {start}")
    data[start + header : start + header + sizeofcmds] = new_cmds + b"\x00" * (
        sizeofcmds - len(new_cmds)
    )
    struct.pack_into("<II", data, start + 16, len(kept), len(new_cmds))
    return removed


def rewrite_file(path: Path) -> None:
    data = bytearray(path.read_bytes())
    if len(data) < 8:
        return
    be_magic = struct.unpack_from(">I", data, 0)[0]
    removed = []
    if be_magic == FAT_MAGIC:
        nfat = struct.unpack_from(">I", data, 4)[0]
        for index in range(nfat):
            offset = struct.unpack_from(">I", data, 8 + index * 20 + 8)[0]
            removed.extend(rewrite_slice(data, offset))
    elif struct.unpack_from("<I", data, 0)[0] == MH_MAGIC_64:
        removed.extend(rewrite_slice(data, 0))
    if not removed:
        return
    path.chmod(path.stat().st_mode | 0o200)
    path.write_bytes(data)
    print(f"Blender iOS: removed load commands from {path.name}: {', '.join(removed)}")


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} DYLIB...", file=sys.stderr)
        return 1
    for arg in sys.argv[1:]:
        path = Path(arg)
        if path.is_file():
            rewrite_file(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
