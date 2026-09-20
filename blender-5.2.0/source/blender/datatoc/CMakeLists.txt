# SPDX-FileCopyrightText: 2023 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later


# -----------------------------------------------------------------------------
# Build `datatoc` executable.
set(SRC
  datatoc.cc
)

# `SRC_DNA_INC` is defined in the parent directory.
if((ANDROID OR IOS) AND HOST_TOOLS_DIR)
  add_executable(datatoc IMPORTED GLOBAL)
  if(ANDROID)
    set_target_properties(datatoc PROPERTIES IMPORTED_LOCATION "${HOST_TOOLS_DIR}/datatoc.exe")
  else()
    set_target_properties(datatoc PROPERTIES IMPORTED_LOCATION "${HOST_TOOLS_DIR}/datatoc")
  endif()
else()
  add_executable(datatoc ${SRC})
  optimize_debug_target(datatoc)
endif()
