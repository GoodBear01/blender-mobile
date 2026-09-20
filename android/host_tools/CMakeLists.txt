# Windows host codegen tools for the Android Blender cross-build.
cmake_minimum_required(VERSION 3.21)
project(blender_android_host_tools C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_BUILD_TYPE Release)
# Keep host binaries in the build root so iOS cmake can find
# $HOST_TOOLS_DIR/{makesdna,makesrna,datatoc,shader_tool}.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}")

set(ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
set(BLENDER "${ROOT}/blender-5.2.0")
if(NOT FMT_INCLUDE)
  foreach(_fmt_cand
      "${BLENDER}/lib/ios_arm64/fmt/include"
      "${BLENDER}/lib/android_arm64/fmt/include")
    if(EXISTS "${_fmt_cand}/fmt/format.h")
      set(FMT_INCLUDE "${_fmt_cand}")
      break()
    endif()
  endforeach()
endif()
if(NOT FMT_INCLUDE)
  set(FMT_INCLUDE "${BLENDER}/extern/fmtlib/include")
endif()

# Do not add iOS OpenImageIO headers here. They are not a macOS include
# tree, and they make blender::UString non-trivially-copyable on Apple Clang.
foreach(_lib_name imath openexr)
  set(_lib_inc "")
  foreach(_root
      "${BLENDER}/lib/ios_arm64/${_lib_name}/include"
      "${BLENDER}/lib/android_arm64/${_lib_name}/include")
    if(EXISTS "${_root}")
      set(_lib_inc "${_root}")
      break()
    endif()
  endforeach()
  if(_lib_inc)
    list(APPEND HOST_DEP_INCLUDES "${_lib_inc}")
  endif()
endforeach()

add_compile_definitions(
  FMT_HEADER_ONLY=1
  WITH_ASSERT_ABORT
)
add_compile_options(-funsigned-char -fpermissive)

file(GLOB DNA_HEADERS "${BLENDER}/source/blender/makesdna/DNA_*.h")
set(DNA_INCLUDE_TEXT "/* generated */\n")
set(DNA_FILE_LIST "/* generated */\n")
foreach(header ${DNA_HEADERS})
  get_filename_component(dna_header_file ${header} NAME)
  string(APPEND DNA_INCLUDE_TEXT "#include \"${header}\"\n")
  string(APPEND DNA_FILE_LIST "\t\"${dna_header_file}\",\n")
endforeach()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/dna_includes_all.h" "${DNA_INCLUDE_TEXT}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/dna_includes_as_strings.h" "${DNA_FILE_LIST}")

include_directories(
  "${CMAKE_CURRENT_LIST_DIR}/stubs"
  "${CMAKE_CURRENT_BINARY_DIR}"
  "${BLENDER}/intern/atomic"
  "${BLENDER}/intern/guardedalloc"
  "${BLENDER}/intern/clog"
  "${BLENDER}/source/blender/blenlib"
  "${BLENDER}/source/blender/makesdna"
  "${BLENDER}/source/blender/makesdna/intern"
  "${FMT_INCLUDE}"
  ${HOST_DEP_INCLUDES}
)

# --- guardedalloc ---
add_library(host_guardedalloc STATIC
  "${BLENDER}/intern/guardedalloc/intern/leak_detector.cc"
  "${BLENDER}/intern/guardedalloc/intern/mallocn.cc"
  "${BLENDER}/intern/guardedalloc/intern/mallocn_guarded_impl.cc"
  "${BLENDER}/intern/guardedalloc/intern/mallocn_lockfree_impl.cc"
  "${BLENDER}/intern/guardedalloc/intern/memory_usage.cc"
)

# --- blenlib subset used by makesdna ---
set(BLENLIB_SRC
  "${BLENDER}/source/blender/blenlib/intern/BLI_assert.cc"
  "${BLENDER}/source/blender/blenlib/intern/BLI_ghash.cc"
  "${BLENDER}/source/blender/blenlib/intern/BLI_ghash_utils.cc"
  "${BLENDER}/source/blender/blenlib/intern/BLI_linklist.cc"
  "${BLENDER}/source/blender/blenlib/intern/BLI_memarena.cc"
  "${BLENDER}/source/blender/blenlib/intern/BLI_mempool.cc"
  "${BLENDER}/source/blender/blenlib/intern/listbase.cc"
  "${BLENDER}/source/blender/blenlib/intern/string.cc"
  "${BLENDER}/source/blender/blenlib/intern/hash_mm2a.cc"
  "${BLENDER}/source/blender/blenlib/intern/gsqueue.cc"
  "${BLENDER}/source/blender/blenlib/intern/threads.cc"
  "${BLENDER}/source/blender/blenlib/intern/time.cc"
  "${BLENDER}/source/blender/blenlib/intern/ustring.cc"
)
add_library(host_blenlib STATIC ${BLENLIB_SRC})
target_link_libraries(host_blenlib PUBLIC host_guardedalloc)

# --- makesdna ---
add_executable(makesdna
  "${BLENDER}/source/blender/makesdna/intern/dna_parse.cc"
  "${BLENDER}/source/blender/makesdna/intern/dna_utils.cc"
  "${BLENDER}/source/blender/makesdna/intern/makesdna.cc"
)
target_compile_definitions(makesdna PRIVATE WITH_DNA_GHASH)
target_link_libraries(makesdna PRIVATE host_blenlib host_guardedalloc)

# Generate DNA for the host makesrna compile.
set(DNA_GEN "${CMAKE_CURRENT_BINARY_DIR}/dna_gen")
file(MAKE_DIRECTORY "${DNA_GEN}")
add_custom_command(
  OUTPUT
    "${DNA_GEN}/dna.cc"
    "${DNA_GEN}/dna_defaults.cc"
    "${DNA_GEN}/dna_struct_ids.cc"
    "${DNA_GEN}/dna_type_offsets.h"
    "${DNA_GEN}/dna_verify.cc"
  COMMAND "$<TARGET_FILE:makesdna>"
    "${DNA_GEN}/dna.cc"
    "${DNA_GEN}/dna_type_offsets.h"
    "${DNA_GEN}/dna_verify.cc"
    "${DNA_GEN}/dna_struct_ids.cc"
    "${DNA_GEN}/dna_defaults.cc"
    "${BLENDER}/source/blender/makesdna/"
  DEPENDS makesdna
  WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
)
add_library(host_dna STATIC
  "${BLENDER}/source/blender/makesdna/intern/dna_genfile.cc"
  "${BLENDER}/source/blender/makesdna/intern/dna_utils.cc"
  "${DNA_GEN}/dna.cc"
  "${DNA_GEN}/dna_struct_ids.cc"
  "${DNA_GEN}/dna_verify.cc"
)
target_compile_definitions(host_dna PUBLIC WITH_DNA_GHASH)
target_include_directories(host_dna PUBLIC "${DNA_GEN}" "${BLENDER}/source/blender/makesdna")
target_link_libraries(host_dna PUBLIC host_blenlib)
set_source_files_properties(
  "${DNA_GEN}/dna.cc" "${DNA_GEN}/dna_struct_ids.cc" "${DNA_GEN}/dna_verify.cc"
  PROPERTIES GENERATED TRUE
)

add_library(host_dna_defaults STATIC
  "${DNA_GEN}/dna_defaults.cc"
  "${BLENDER}/release/datafiles/userdef/userdef_default_theme.c"
)
target_include_directories(host_dna_defaults PUBLIC "${DNA_GEN}")
target_link_libraries(host_dna_defaults PUBLIC host_dna)
set_source_files_properties("${DNA_GEN}/dna_defaults.cc" PROPERTIES GENERATED TRUE)

add_library(host_clog STATIC "${BLENDER}/intern/clog/clog.cc")

# --- makesrna ---
file(GLOB RNA_DEF_SRC "${BLENDER}/source/blender/makesrna/intern/rna_*.cc")
list(FILTER RNA_DEF_SRC EXCLUDE REGEX "rna_access")
list(FILTER RNA_DEF_SRC EXCLUDE REGEX "rna_define\\.cc$")
list(FILTER RNA_DEF_SRC EXCLUDE REGEX "rna_path\\.cc$")

add_executable(makesrna
  "${BLENDER}/source/blender/makesrna/intern/makesrna.cc"
  "${BLENDER}/source/blender/makesrna/intern/makesrna_utils.cc"
  "${BLENDER}/source/blender/makesrna/intern/rna_define.cc"
  ${RNA_DEF_SRC}
  "${BLENDER}/intern/clog/clog.cc"
  "${BLENDER}/source/blender/makesdna/intern/dna_parse.cc"
)
target_include_directories(makesrna PRIVATE
  "${BLENDER}/source/blender/makesrna"
  "${BLENDER}/source/blender/makesrna/intern"
  "${BLENDER}/source/blender/animrig"
  "${BLENDER}/source/blender/asset_system"
  "${BLENDER}/source/blender/blenfont"
  "${BLENDER}/source/blender/blenkernel"
  "${BLENDER}/source/blender/blenloader"
  "${BLENDER}/source/blender/blentranslation"
  "${BLENDER}/source/blender/bmesh"
  "${BLENDER}/source/blender/depsgraph"
  "${BLENDER}/source/blender/draw"
  "${BLENDER}/source/blender/functions"
  "${BLENDER}/source/blender/gpu"
  "${BLENDER}/source/blender/ikplugin"
  "${BLENDER}/source/blender/imbuf"
  "${BLENDER}/source/blender/imbuf/movie"
  "${BLENDER}/source/blender/io/usd"
  "${BLENDER}/source/blender/modifiers"
  "${BLENDER}/source/blender/nodes"
  "${BLENDER}/source/blender/nodes/composite/include"
  "${BLENDER}/source/blender/nodes/function/include"
  "${BLENDER}/source/blender/nodes/geometry/include"
  "${BLENDER}/source/blender/sequencer"
  "${BLENDER}/source/blender/simulation"
  "${BLENDER}/source/blender/windowmanager"
  "${BLENDER}/source/blender/editors/asset"
  "${BLENDER}/source/blender/editors/include"
  "${BLENDER}/source/blender/render"
  "${BLENDER}/source/blender/python"
  "${DNA_GEN}"
)
target_compile_definitions(makesrna PRIVATE
  WITH_PYTHON
  WITH_VULKAN_BACKEND
  WITH_SDL
  WITH_DNA_GHASH
)
target_link_libraries(makesrna PRIVATE host_dna host_dna_defaults host_blenlib host_guardedalloc)

# --- datatoc ---
add_executable(datatoc "${BLENDER}/source/blender/datatoc/datatoc.cc")

# --- shader_tool ---
add_executable(shader_tool
  "${BLENDER}/source/blender/gpu/shader_tool/attribute.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/enum.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/flow_control.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/function.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/grammar.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/intermediate.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/metadata.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/namespace.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/processor.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/resource_table.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/shader_tool.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/string.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/struct.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/template.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/union.cc"
  "${BLENDER}/source/blender/gpu/shader_tool/lexit/lexit.cc"
)
target_include_directories(shader_tool PRIVATE
  "${BLENDER}/source/blender/gpu"
  "${BLENDER}/source/blender/gpu/shader_tool"
)
