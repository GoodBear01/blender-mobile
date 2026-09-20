/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 *
 * Shared phone-host flags. Android and iOS both run the SDL + Vulkan
 * single-window path; macOS Cocoa/Metal stays desktop-only.
 */

#pragma once

#if defined(__APPLE__)
#  include <TargetConditionals.h>
#  if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#    ifndef BLENDER_IOS
#      define BLENDER_IOS 1
#    endif
#  endif
#endif

#if defined(__ANDROID__) || defined(BLENDER_IOS)
#  ifndef BLENDER_MOBILE
#    define BLENDER_MOBILE 1
#  endif
#endif
