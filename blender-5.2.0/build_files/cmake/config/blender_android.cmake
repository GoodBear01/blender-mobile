# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Experimental Android (arm64) configuration.
# Usage:
#   cmake -C build_files/cmake/config/blender_android.cmake \
#         -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
#         -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 ...

include(${CMAKE_CURRENT_LIST_DIR}/blender_lite.cmake)

set(WITH_GHOST_SDL            ON  CACHE BOOL "" FORCE)
set(WITH_GHOST_X11            OFF CACHE BOOL "" FORCE)
set(WITH_GHOST_WAYLAND        OFF CACHE BOOL "" FORCE)
set(WITH_GHOST_XDND           OFF CACHE BOOL "" FORCE)
set(WITH_X11_XINPUT           OFF CACHE BOOL "" FORCE)
set(WITH_VULKAN_BACKEND       ON  CACHE BOOL "" FORCE)
set(WITH_OPENGL_BACKEND       OFF CACHE BOOL "" FORCE)
set(WITH_METAL_BACKEND        OFF CACHE BOOL "" FORCE)
set(WITH_HEADLESS             OFF CACHE BOOL "" FORCE)
set(WITH_PYTHON               ON  CACHE BOOL "" FORCE)
set(WITH_PYTHON_INSTALL       OFF CACHE BOOL "" FORCE)
set(WITH_INPUT_NDOF           OFF CACHE BOOL "" FORCE)
set(WITH_INPUT_IME            OFF CACHE BOOL "" FORCE)
set(WITH_CPU_CHECK            OFF CACHE BOOL "" FORCE)
set(WITH_INSTALL_PORTABLE     ON  CACHE BOOL "" FORCE)
set(WITH_COMPILER_SIMD        OFF CACHE BOOL "" FORCE)
set(WITH_TBB                  ON  CACHE BOOL "" FORCE)
set(WITH_TBB_MALLOC_PROXY     OFF CACHE BOOL "" FORCE)
set(WITH_XR_OPENXR            OFF CACHE BOOL "" FORCE)
set(WITH_PULSEAUDIO           OFF CACHE BOOL "" FORCE)
set(WITH_PIPEWIRE             OFF CACHE BOOL "" FORCE)
set(WITH_JACK                 OFF CACHE BOOL "" FORCE)
set(WITH_OPENAL               OFF CACHE BOOL "" FORCE)
set(WITH_SDL_AUDIO            OFF CACHE BOOL "" FORCE)
set(WITH_AUDASPACE            OFF CACHE BOOL "" FORCE)
set(WITH_LIBS_PRECOMPILED     ON  CACHE BOOL "" FORCE)
set(WITH_STATIC_LIBS          ON  CACHE BOOL "" FORCE)
set(WITH_SYSTEM_FREETYPE      OFF CACHE BOOL "" FORCE)
set(WITH_GHOST_DEBUG          OFF CACHE BOOL "" FORCE)
set(WITH_UNITY_BUILD          ON  CACHE BOOL "" FORCE)
set(WITH_GTESTS               OFF CACHE BOOL "" FORCE)
set(WITH_DOC_MANPAGE          OFF CACHE BOOL "" FORCE)
# CPU Cycles only: phones have no CUDA/HIP/OptiX.
set(WITH_CYCLES               ON  CACHE BOOL "" FORCE)
set(WITH_CYCLES_DEVICE_CUDA   OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES_DEVICE_HIP    OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES_DEVICE_OPTIX  OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES_DEVICE_ONEAPI OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES_OSL           OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES_EMBREE        OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES_PATH_GUIDING  OFF CACHE BOOL "" FORCE)
# Host-generated RNA wrappers bake sizeof(PointerRNA). Keep NDEBUG so the
# NDK Vector/PointerRNA layout matches the Windows makesrna tool.
set(WITH_ASSERT_RELEASE       OFF CACHE BOOL "" FORCE)
