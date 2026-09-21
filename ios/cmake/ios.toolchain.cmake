# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Device-only iphoneos arm64 toolchain. Run this from a Mac with Xcode.

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "" FORCE)
set(IOS TRUE)

execute_process(
  COMMAND xcrun --sdk iphoneos --show-sdk-path
  OUTPUT_VARIABLE _ios_sdk
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT _ios_sdk)
  message(FATAL_ERROR "xcrun could not find the iphoneos SDK")
endif()
set(CMAKE_OSX_SYSROOT "${_ios_sdk}" CACHE PATH "" FORCE)
unset(_ios_sdk)

execute_process(
  COMMAND xcrun --sdk iphoneos -f clang
  OUTPUT_VARIABLE _ios_cc
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
  COMMAND xcrun --sdk iphoneos -f clang++
  OUTPUT_VARIABLE _ios_cxx
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(_ios_cc)
  set(CMAKE_C_COMPILER "${_ios_cc}" CACHE FILEPATH "" FORCE)
endif()
if(_ios_cxx)
  set(CMAKE_CXX_COMPILER "${_ios_cxx}" CACHE FILEPATH "" FORCE)
endif()
unset(_ios_cc)
unset(_ios_cxx)

set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
string(APPEND CMAKE_C_FLAGS_INIT " -funsigned-char")
string(APPEND CMAKE_CXX_FLAGS_INIT " -funsigned-char")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
