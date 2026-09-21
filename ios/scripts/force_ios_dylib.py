#!/usr/bin/env python3
"""Make source/creator/CMakeLists.txt emit libblender.dylib even on a stale tree."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "BLENDER_IOS_FORCE_DYLIB" in text:
    sys.exit(0)
needle = "if(WITH_PYTHON_MODULE)"
if needle not in text:
    sys.stderr.write("force_ios_dylib: if(WITH_PYTHON_MODULE) not found\n")
    sys.exit(1)
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
text = text.replace(needle, block, 1)
path.write_text(text, encoding="utf-8")
print("Blender iOS: patched creator CMakeLists to emit libblender.dylib")
