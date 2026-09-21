#!/usr/bin/env python3
"""Ensure creator CMakeLists.txt can emit libblender.dylib.

An earlier version of this script replaced the substring
if(WITH_PYTHON_MODULE) inside elseif(WITH_PYTHON_MODULE), which produced a
bare `else` and a CMake parse error at line 320. Undo that, then insert a
real iOS branch only when the file is still the stock Blender layout.
"""
from __future__ import annotations

import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
original = text

# Undo the broken insertion: "elseif" lost its "if(" and became "else".
text = re.sub(
    r"else# BLENDER_IOS_FORCE_DYLIB\n"
    r"if\(IOS OR CMAKE_SYSTEM_NAME STREQUAL \"iOS\" OR LIBDIR MATCHES \"ios_arm64\"\).*?"
    r"elseif\(WITH_PYTHON_MODULE\)\n",
    "elseif(WITH_PYTHON_MODULE)\n",
    text,
    count=1,
    flags=re.S,
)
# Undo a clean insertion if we need to rewrite.
text = re.sub(
    r"\n# BLENDER_IOS_FORCE_DYLIB\n"
    r"if\(IOS OR CMAKE_SYSTEM_NAME STREQUAL \"iOS\" OR LIBDIR MATCHES \"ios_arm64\"\).*?"
    r"elseif\(WITH_PYTHON_MODULE\)\n",
    "\nif(WITH_PYTHON_MODULE)\n",
    text,
    count=1,
    flags=re.S,
)

has_ios_dylib = "add_library(blender SHARED" in text and "ios_arm64" in text
if has_ios_dylib:
    if text != original:
        path.write_text(text, encoding="utf-8")
        print("Blender iOS: repaired creator CMakeLists.txt")
    sys.exit(0)

block = """# BLENDER_IOS_FORCE_DYLIB
if(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS" OR LIBDIR MATCHES "ios_arm64")
  add_library(blender SHARED ${SRC})
  set_target_properties(blender PROPERTIES
    OUTPUT_NAME blender PREFIX "lib" SUFFIX ".dylib"
    FRAMEWORK OFF BUNDLE OFF MACOSX_BUNDLE OFF
    MACOSX_RPATH ON INSTALL_NAME_DIR "@rpath")
  target_compile_definitions(blender PRIVATE BLENDER_IOS BLENDER_MOBILE)
  if(EXISTS "${LIBDIR}/vulkan/include")
    target_include_directories(blender PRIVATE ${LIBDIR}/vulkan/include)
  endif()
  target_link_libraries(blender PRIVATE SDL3::SDL3)
  if(DEFINED MOLTENVK_LIBRARY AND EXISTS "${MOLTENVK_LIBRARY}")
    target_link_libraries(blender PRIVATE "${MOLTENVK_LIBRARY}")
  endif()
  target_link_options(blender PRIVATE "-Wl,-rpath,@executable_path/Frameworks")
elseif(WITH_PYTHON_MODULE)
"""
new, n = re.subn(r"(?m)^if\(WITH_PYTHON_MODULE\)", block, text, count=1)
if n != 1:
    sys.stderr.write("force_ios_dylib: no leading if(WITH_PYTHON_MODULE) to patch\n")
    if text != original:
        path.write_text(text, encoding="utf-8")
    sys.exit(1)
path.write_text(new, encoding="utf-8")
print("Blender iOS: patched creator CMakeLists to emit libblender.dylib")
