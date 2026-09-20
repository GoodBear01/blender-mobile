# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# iOS platform file. Expects prebuilt deps in lib/ios_arm64
# produced by ios/scripts/build_deps.sh on a Mac.

if(NOT IOS AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "platform_ios.cmake is only for iOS toolchains")
endif()

set(IOS TRUE)

set(WITH_GHOST_X11 OFF CACHE BOOL "" FORCE)
set(WITH_GHOST_WAYLAND OFF CACHE BOOL "" FORCE)
set(WITH_GHOST_SDL ON CACHE BOOL "" FORCE)
set(WITH_OPENGL_BACKEND OFF CACHE BOOL "" FORCE)
set(WITH_VULKAN_BACKEND ON CACHE BOOL "" FORCE)
set(WITH_METAL_BACKEND OFF CACHE BOOL "" FORCE)
set(WITH_CPU_CHECK OFF CACHE BOOL "" FORCE)
set(WITH_TBB_MALLOC_PROXY OFF CACHE BOOL "" FORCE)
set(WITH_XR_OPENXR OFF CACHE BOOL "" FORCE)
set(WITH_HEADLESS OFF)

if(NOT DEFINED LIBDIR)
  set(LIBDIR ${CMAKE_SOURCE_DIR}/lib/ios_arm64)
endif()

if(NOT EXISTS "${LIBDIR}/zlib" AND NOT EXISTS "${LIBDIR}/sdl")
  message(FATAL_ERROR
    "iOS libraries are missing at ${LIBDIR}.\n"
    "That empty folder is why cmake prints a wall of find_package errors.\n"
    "For a phone install today, open ios/BlenderMobile.xcodeproj (the stub).\n"
    "For the full editor, run ./ios/scripts/build_deps.sh on this Mac first.")
endif()

message(STATUS "iOS LIBDIR: ${LIBDIR}")

file(GLOB LIB_SUBDIRS ${LIBDIR}/*)
set(CMAKE_PREFIX_PATH ${LIBDIR} ${LIBDIR}/zlib ${LIB_SUBDIRS})
set(CMAKE_FIND_ROOT_PATH ${LIBDIR} ${CMAKE_FIND_ROOT_PATH})
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)

set(WITH_STATIC_LIBS ON)
set(OPENEXR_ROOT_DIR ${LIBDIR}/openexr)
set(OpenImageIO_ROOT ${LIBDIR}/openimageio)
set(OpenColorIO_ROOT ${LIBDIR}/opencolorio)
set(OpenEXR_ROOT ${LIBDIR}/openexr)
set(Imath_ROOT ${LIBDIR}/imath)
set(fmt_ROOT ${LIBDIR}/fmt)
set(fmt_DIR ${LIBDIR}/fmt/lib/cmake/fmt)
set(VULKAN_ROOT_DIR ${LIBDIR}/vulkan)
set(SHADERC_ROOT_DIR ${LIBDIR}/shaderc)
set(ZSTD_ROOT_DIR ${LIBDIR}/zstd)
set(BROTLI_ROOT_DIR ${LIBDIR}/brotli)
set(JPEG_ROOT ${LIBDIR}/jpeg)
set(PNG_ROOT ${LIBDIR}/png)
set(ZLIB_ROOT ${LIBDIR}/zlib)
set(TIFF_ROOT ${LIBDIR}/tiff)
set(TIFF_DIR ${LIBDIR}/tiff/lib/cmake/tiff)
set(SDL3_DIR ${LIBDIR}/sdl/lib/cmake/SDL3)
set(TBB_DIR ${LIBDIR}/tbb/lib/cmake/TBB)
set(Eigen3_DIR ${LIBDIR}/eigen/share/eigen3/cmake)
set(Python_ROOT ${LIBDIR}/python)
set(PYTHON_ROOT_DIR ${LIBDIR}/python)
set(PYTHON_LINKFLAGS "" CACHE STRING "Linker flags for python" FORCE)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

if(NOT PYTHON_EXECUTABLE)
  find_program(PYTHON_EXECUTABLE NAMES python3 python)
endif()

if(NOT TARGET CMath::CMath)
  add_library(CMath::CMath INTERFACE IMPORTED)
  set_target_properties(CMath::CMath PROPERTIES INTERFACE_LINK_LIBRARIES "m")
endif()

if(NOT COMMAND find_package_static)
  macro(find_package_static)
    set(_cmake_find_library_suffixes_back ${CMAKE_FIND_LIBRARY_SUFFIXES})
    set(CMAKE_FIND_LIBRARY_SUFFIXES .a ${CMAKE_FIND_LIBRARY_SUFFIXES})
    find_package(${ARGV})
    set(CMAKE_FIND_LIBRARY_SUFFIXES ${_cmake_find_library_suffixes_back})
    unset(_cmake_find_library_suffixes_back)
  endmacro()
endif()

macro(find_package_wrapper)
  find_package_static(${ARGV})
endmacro()

if(DEFINED LIBDIR)
  without_system_libs_begin()
endif()

find_package_wrapper(JPEG REQUIRED)
find_package_wrapper(PNG REQUIRED)
find_package_wrapper(ZLIB REQUIRED)
find_package_wrapper(Zstd REQUIRED)
find_package_wrapper(fmt REQUIRED)

if(DEFINED fmt_DIR)
  mark_as_advanced(fmt_DIR)
endif()

if(WITH_VULKAN_BACKEND)
  if(NOT DEFINED VULKAN_ROOT_DIR)
    set(VULKAN_ROOT_DIR ${LIBDIR}/vulkan)
  endif()
  if(NOT DEFINED SHADERC_ROOT_DIR)
    set(SHADERC_ROOT_DIR ${LIBDIR}/shaderc)
  endif()
  if(NOT Vulkan_INCLUDE_DIR AND EXISTS "${LIBDIR}/vulkan/include/vulkan/vulkan.h")
    set(Vulkan_INCLUDE_DIR "${LIBDIR}/vulkan/include" CACHE PATH "" FORCE)
  endif()
  if(NOT Vulkan_LIBRARY)
    file(GLOB _mvk_cands
      "${LIBDIR}/moltenvk/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
      "${LIBDIR}/moltenvk/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK"
      "${LIBDIR}/moltenvk/lib/libMoltenVK.a"
      "${LIBDIR}/moltenvk/lib/libMoltenVK.dylib"
    )
    if(_mvk_cands)
      list(GET _mvk_cands 0 Vulkan_LIBRARY)
      set(Vulkan_LIBRARY "${Vulkan_LIBRARY}" CACHE FILEPATH "" FORCE)
      set(MOLTENVK_LIBRARY "${Vulkan_LIBRARY}" CACHE FILEPATH "" FORCE)
    endif()
    unset(_mvk_cands)
  endif()
  find_package_wrapper(Vulkan REQUIRED)
  find_package_wrapper(ShaderC REQUIRED)
endif()

if(EXISTS "${LIBDIR}/python/include/python3.13/Python.h")
  set(PYTHON_INCLUDE_DIR "${LIBDIR}/python/include/python3.13" CACHE PATH "" FORCE)
  set(PYTHON_INCLUDE_CONFIG_DIR "${LIBDIR}/python/include/python3.13" CACHE PATH "" FORCE)
endif()
if(EXISTS "${LIBDIR}/python/lib/libpython3.13.a")
  set(PYTHON_LIBRARY "${LIBDIR}/python/lib/libpython3.13.a" CACHE FILEPATH "" FORCE)
elseif(EXISTS "${LIBDIR}/python/lib/libpython3.13.dylib")
  set(PYTHON_LIBRARY "${LIBDIR}/python/lib/libpython3.13.dylib" CACHE FILEPATH "" FORCE)
endif()
if(EXISTS "${LIBDIR}/python/lib/python3.13/abc.py")
  set(PYTHON_LIBPATH "${LIBDIR}/python/lib" CACHE PATH "" FORCE)
endif()

if(NOT WITH_SYSTEM_FREETYPE)
  find_package_wrapper(Freetype REQUIRED)
  if(DEFINED LIBDIR)
    find_package_wrapper(Brotli REQUIRED)
  else()
    set(BROTLI_LIBRARIES "")
  endif()
endif()

if(WITH_PYTHON)
  find_package(PythonLibsUnix REQUIRED)
else()
  find_program(PYTHON_EXECUTABLE "python3")
endif()

if(NOT TARGET openjph)
  set(_openjph_lib "${LIBDIR}/openjph/lib/libopenjph.a")
  if(NOT EXISTS "${_openjph_lib}")
    set(_openjph_lib "${LIBDIR}/openexr/lib/libopenjph.a")
  endif()
  if(EXISTS "${_openjph_lib}")
    add_library(openjph STATIC IMPORTED)
    set_target_properties(openjph PROPERTIES IMPORTED_LOCATION "${_openjph_lib}")
  endif()
  unset(_openjph_lib)
endif()
find_package_wrapper(OpenEXR REQUIRED)
if(DEFINED OpenEXR_DIR)
  mark_as_advanced(OpenEXR_DIR)
endif()
if(DEFINED Imath_DIR)
  mark_as_advanced(Imath_DIR)
endif()

if(WITH_IMAGE_OPENJPEG)
  find_package_wrapper(OpenJPEG)
  set_and_warn_library_found("OpenJPEG" OPENJPEG_FOUND WITH_IMAGE_OPENJPEG)
endif()

if(WITH_SDL)
  find_package(SDL3 CONFIG)
  set_and_warn_library_found("SDL" SDL3_FOUND WITH_SDL)
endif()

if(WITH_IMAGE_WEBP)
  find_package_wrapper(WebP)
  set_and_warn_library_found("WebP" WEBP_FOUND WITH_IMAGE_WEBP)
endif()

find_package_wrapper(OpenImageIO REQUIRED)
if(DEFINED OpenImageIO_DIR)
  mark_as_advanced(OpenImageIO_DIR)
endif()

find_package_wrapper(OpenColorIO 2.0.0 REQUIRED)
if(DEFINED OpenColorIO_DIR)
  mark_as_advanced(OpenColorIO_DIR)
endif()

if(WITH_TBB)
  find_package_wrapper(TBB)
  if(TBB_FOUND)
    get_target_property(TBB_LIBRARIES TBB::tbb LOCATION)
    get_target_property(TBB_INCLUDE_DIRS TBB::tbb INTERFACE_INCLUDE_DIRECTORIES)
  endif()
  set_and_warn_library_found("TBB" TBB_FOUND WITH_TBB)
  mark_as_advanced(TBB_DIR)
endif()

if(WITH_POTRACE)
  find_package_wrapper(Potrace)
  set_and_warn_library_found("Potrace" POTRACE_FOUND WITH_POTRACE)
endif()

find_package_wrapper(TIFF)

if(WITH_HARFBUZZ)
  find_package(Harfbuzz)
endif()
if(WITH_FRIBIDI)
  find_package(Fribidi)
endif()

if(WITH_PUGIXML)
  find_package_wrapper(PugiXML)
  set_and_warn_library_found("PugiXML" PUGIXML_FOUND WITH_PUGIXML)
endif()

if(EXISTS "${LIBDIR}/eigen")
  set(Eigen3_ROOT ${LIBDIR}/eigen)
endif()
find_package_wrapper(Eigen3 REQUIRED)
if(DEFINED Eigen3_DIR)
  mark_as_advanced(Eigen3_DIR)
endif()

find_package(Threads REQUIRED)
if(CMAKE_THREAD_LIBS_INIT)
  list(APPEND PLATFORM_LINKLIBS ${CMAKE_THREAD_LIBS_INIT})
  set(PTHREADS_LIBRARIES ${CMAKE_THREAD_LIBS_INIT})
endif()

if(DEFINED LIBDIR)
  without_system_libs_end()
endif()

# MoltenVK + UIKit. The Xcode app also embeds these frameworks.
set(PLATFORM_LINKLIBS
  "-framework Foundation"
  "-framework UIKit"
  "-framework Metal"
  "-framework QuartzCore"
  "-framework CoreGraphics"
  "-framework CoreFoundation"
  "-framework GameController"
  "-framework AudioToolbox"
  "-framework AVFoundation"
  "-framework CoreHaptics"
  "-framework CoreMotion"
  "-framework OpenGLES"
  m
  c++
)

set(PLATFORM_CFLAGS "-fPIC -fexceptions -frtti -DBLENDER_IOS -DBLENDER_MOBILE")
set(PLATFORM_CFLAGS "${PLATFORM_CFLAGS} -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64")
set(PLATFORM_LINKFLAGS "-Wl,-dead_strip")
set(PLATFORM_LINKFLAGS_DEBUG "")

set(WITH_INSTALL_PORTABLE ON)
set(PLATFORM_BUNDLED_LIBRARIES "")
set(HAVE_EXECINFO_H FALSE)

add_definitions(-DBLENDER_IOS)
add_definitions(-DBLENDER_MOBILE)
add_definitions(-DTARGET_OS_IPHONE=1)
