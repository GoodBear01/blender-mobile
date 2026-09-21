/* SPDX-FileCopyrightText: 2001-2002 NaN Holding BV. All rights reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup creator
 */

#include <cstdlib>
#include <cstring>

#ifdef WIN32
#  ifdef WIN32_LEAN_AND_MEAN
#    undef WIN32_LEAN_AND_MEAN
#  endif
#  include "utfconv.hh"
#  include <windows.h>
#  ifdef WITH_CPU_CHECK
#    pragma comment(linker, "/include:cpu_check_win32")
#  endif
#endif

#if defined(WITH_TBB_MALLOC) && defined(_MSC_VER) && defined(NDEBUG)
#  pragma comment(lib, "tbbmalloc_proxy.lib")
#  pragma comment(linker, "/include:__TBB_malloc_proxy")
#endif

#include "MEM_guardedalloc.h"

#include "CLG_log.h"

#include "DNA_genfile.h"

#include "BLI_endian_defines.h"
#include "BLI_fftw.hh"
#include "BLI_path_utils.hh"
#include "BLI_string.h"
#include "BLI_system.h"
#include "BLI_task.h"
#include "BLI_threads.h"
#include "BLI_utildefines.h"

/* Mostly initialization functions. */
#include "BKE_appdir.hh"
#include "BKE_blender.hh"
#include "BKE_brush.hh"
#include "BKE_callbacks.hh"
#include "BKE_context.hh"
#include "BKE_cpp_types.hh"
#include "BKE_global.hh"
#include "BKE_idtype.hh"
#include "BKE_material.hh"
#include "BKE_modifier.hh"
#include "BKE_node.hh"
#include "BKE_particle.h"
#include "BKE_shader_fx.hh"
#include "BKE_sound.hh"
#include "BKE_vfont.hh"
#include "BKE_volume.hh"

#ifndef WITH_PYTHON_MODULE
#  include "BLI_args.h"
#endif

#include "DEG_depsgraph.hh"

#include "IMB_imbuf.hh" /* For #IMB_init. */

#include "MOV_util.hh"

#include "RE_engine.h"
#include "RE_texture.h"

#include "ED_datafiles.h"

#include "SEQ_modifier.hh"

#include "WM_api.hh"

#include "RNA_define.hh"

#if defined(__ANDROID__) || defined(BLENDER_IOS)
/* Provide our own C entry; do not let SDL_main.h rename int main(). */
#  define SDL_MAIN_HANDLED
#  include <SDL3/SDL_hints.h>
#  include <SDL3/SDL_main.h>
#endif
#ifdef __ANDROID__
#  include <android/log.h>
#endif

#include "FN_init.hh"

#ifdef WITH_OPENGL_BACKEND
#  include "GPU_compilation_subprocess.hh"
#endif

#ifdef WITH_FREESTYLE
#  include "FRS_freestyle.h"
#endif

#include <csignal>

#ifdef __FreeBSD__
#  include <floatingpoint.h>
#endif

#ifdef WITH_BINRELOC
#  include "binreloc.h"
#endif

#ifdef WITH_LIBMV
#  include "libmv-capi.h"
#endif

#ifdef WITH_CYCLES
#  include "CCL_api.h"
#endif

#if defined(WITH_PYTHON_MODULE) && defined(__APPLE__)
/* Environment is not available in macOS shared libraries. */
#  include <crt_externs.h>
char **environ = nullptr;
#endif

#if defined(WITH_TBB_MALLOC) && defined(__linux__)
#  include <tbb/scalable_allocator.h>
#endif

#include "creator_intern.h" /* Own include. */

BLI_STATIC_ASSERT(ENDIAN_ORDER == L_ENDIAN, "Blender only builds on little endian systems")

/* -------------------------------------------------------------------- */
/** \name GMP Allocator Workaround
 * \{ */

#if (defined(WITH_TBB_MALLOC) && defined(_MSC_VER) && defined(NDEBUG) && defined(WITH_GMP)) || \
    defined(DOXYGEN)
#  include "gmp.h"
#  include "tbb/scalable_allocator.h"

void *gmp_alloc(size_t size)
{
  return scalable_malloc(size);
}
void *gmp_realloc(void *ptr, size_t /*old_size*/, size_t new_size)
{
  return scalable_realloc(ptr, new_size);
}

void gmp_free(void *ptr, size_t /*size*/)
{
  scalable_free(ptr);
}
/**
 * Use TBB's scalable_allocator on Windows.
 * `TBBmalloc` correctly captures all allocations already,
 * however, GMP is built with MINGW since it doesn't build with MSVC,
 * which TBB has issues hooking into automatically.
 */
void gmp_blender_init_allocator()
{
  mp_set_memory_functions(gmp_alloc, gmp_realloc, gmp_free);
}
#endif

/** \} */

/* -------------------------------------------------------------------- */
/** \name Local Defines
 * \{ */

/* When building as a Python module, don't use special argument handling
 * so the module loading logic can control the `argv` & `argc`. */
#if defined(WIN32) && !defined(WITH_PYTHON_MODULE)
#  define USE_WIN32_UNICODE_ARGS
#endif

/** \} */

namespace blender {

/* -------------------------------------------------------------------- */
/** \name Local Application State
 * \{ */

/* Written to by `creator_args.cc`. */
ApplicationState app_state = []() {
  ApplicationState app_state{};
  app_state.signal.use_crash_handler = true;
  app_state.signal.use_console_crash_handler = false;
  app_state.signal.use_abort_handler = true;
  app_state.exit_code_on_error.python = 0;
  app_state.main_arg_deferred = nullptr;
  return app_state;
}();

/** \} */

/* -------------------------------------------------------------------- */
/** \name Application Level Callbacks
 *
 * Initialize callbacks for the modules that need them.
 * \{ */

static void callback_mem_error(const char *errorStr)
{
  fputs(errorStr, stderr);
  fflush(stderr);
}

static void main_callback_setup()
{
  /* Error output from the guarded allocation routines. */
  MEM_set_error_callback(callback_mem_error);
}

/** Data to free when Blender exits early on. */
struct CreatorAtExitData_EarlyExit {
  bContext *C;
};

/** Free data on early exit (if Python calls `sys.exit()` while parsing args for eg). */
struct CreatorAtExitData {
#ifndef WITH_PYTHON_MODULE
  bArgs *ba;
#endif

#ifdef USE_WIN32_UNICODE_ARGS
  char **argv;
  int argv_num;
#endif

  /**
   * When non-null, run additional exit logic.
   * Cleared once early initialization is over.
   */
  CreatorAtExitData_EarlyExit *early_exit = nullptr;
};

static void callback_main_atexit(void *user_data)
{
  CreatorAtExitData *app_init_data = static_cast<CreatorAtExitData *>(user_data);

#ifndef WITH_PYTHON_MODULE
  if (app_init_data->ba) {
    BLI_args_destroy(app_init_data->ba);
    app_init_data->ba = nullptr;
  }
#endif

#ifdef USE_WIN32_UNICODE_ARGS
  if (app_init_data->argv) {
    while (app_init_data->argv_num) {
      free((void *)app_init_data->argv[--app_init_data->argv_num]);
    }
    free((void *)app_init_data->argv);
    app_init_data->argv = nullptr;
  }
#endif

  if (CreatorAtExitData_EarlyExit *early_exit = app_init_data->early_exit) {
    CTX_free(early_exit->C);

    DEG_free_node_types();

    BKE_blender_globals_clear();
    BKE_appdir_exit();

    DNA_sdna_current_free();

    CLG_exit();
  }
}

static void callback_clg_fatal(void *fp)
{
  BLI_system_backtrace(static_cast<FILE *>(fp));
}

/** \} */

/* -------------------------------------------------------------------- */
/** \name LD_PRELOAD for Linux
 * \{ */

static void restore_ld_preload()
{
  /* LD_PRELOAD may have been modified on startup for Blender. However
   * we don't want it for other executables launched from Blender. */
  const char *restore_ld_preload = BLI_getenv("BLENDER_RESTORE_LD_PRELOAD");
  if (restore_ld_preload) {
    BLI_setenv("LD_PRELOAD", restore_ld_preload);
  }
}

/** \} */

/* -------------------------------------------------------------------- */
/** \name Blender as a Stand-Alone Python Module (bpy)
 *
 * While not officially supported, this can be useful for Python developers.
 * See: https://developer.blender.org/docs/handbook/building_blender/python_module/
 * \{ */

#ifdef WITH_PYTHON_MODULE
static void *main_python_evil_C = nullptr;

/* Called in `bpy_interface.cc` when building as a Python module. */
int main_python_enter(int argc, const char **argv);

void main_python_exit()
{
  WM_exit_ex((bContext *)main_python_evil_C, true, false);
  main_python_evil_C = nullptr;
}

/* Rename the `main(..)` function, allowing Python initialization to call it. */
#  define main blender::main_python_enter
#endif /* WITH_PYTHON_MODULE */

/** \} */

}  // namespace blender

/* -------------------------------------------------------------------- */
/** \name Main Function
 * \{ */

#if defined(__APPLE__) && !defined(BLENDER_IOS)
extern "C" int GHOST_HACK_getFirstFile(char buf[]);
#endif

/**
 * Blender's main function responsibilities are:
 * - setup subsystems.
 * - handle arguments.
 * - run #WM_main() event loop,
 *   or exit immediately when running in background-mode.
 */
int main(int argc,
#ifdef USE_WIN32_UNICODE_ARGS
         const char ** /*argv_c*/
#else
         const char **argv
#endif
)
{
  using namespace blender;

#if defined(__ANDROID__) || defined(BLENDER_IOS)
  static const char *mobile_argv_fallback[] = {"blender", "--gpu-backend", "vulkan", nullptr};
  if (argc < 1 || argv == nullptr) {
    argc = 3;
    argv = mobile_argv_fallback;
  }
#endif

  bContext *C;
#ifndef WITH_PYTHON_MODULE
  bArgs *ba;
#endif

  /* Ensure we free data on early-exit. */
  CreatorAtExitData app_init_data = {nullptr};
  BKE_blender_atexit_register(callback_main_atexit, &app_init_data);

  CreatorAtExitData_EarlyExit app_init_data_early_exit = {nullptr};
  app_init_data.early_exit = &app_init_data_early_exit;

/* Un-buffered `stdout` makes `stdout` and `stderr` better synchronized, and helps
 * when stepping through code in a debugger (prints are immediately
 * visible). However disabling buffering causes lock contention on windows
 * see #76767 for details, since this is a debugging aid, we do not enable
 * the un-buffered behavior for release builds. */
#ifndef NDEBUG
  setvbuf(stdout, nullptr, _IONBF, 0);
#endif

  restore_ld_preload();

#ifdef WIN32
#  ifdef USE_WIN32_UNICODE_ARGS
  /* Win32 Unicode Arguments. */
  {
    /* NOTE: Can't use `guardedalloc` allocation here, as it's not yet initialized
     * (it depends on the arguments passed in, which is what we're getting here!). */
    wchar_t **argv_16 = CommandLineToArgvW(GetCommandLineW(), &argc);
    app_init_data.argv = static_cast<char **>(malloc(argc * sizeof(char *)));
    for (int i = 0; i < argc; i++) {
      app_init_data.argv[i] = alloc_utf_8_from_16(argv_16[i], 0);
    }
    LocalFree(argv_16);

    /* Free on early-exit. */
    app_init_data.argv_num = argc;
  }
  const char **argv = const_cast<const char **>(app_init_data.argv);
#  endif /* USE_WIN32_UNICODE_ARGS */
#endif   /* WIN32 */

#if defined(WITH_OPENGL_BACKEND) && BLI_SUBPROCESS_SUPPORT
  if (STREQ(argv[0], "--compilation-subprocess")) {
    BLI_assert(argc == 2);
    GPU_compilation_subprocess_run(argv[1]);
    return 0;
  }
#endif

#if defined(WITH_TBB_MALLOC) && defined(__linux__)
  /* Enable huge pages for performance. */
  scalable_allocation_mode(TBBMALLOC_USE_HUGE_PAGES, 1);
#endif

  /* NOTE: Special exception for guarded allocator type switch:
   *       we need to perform switch from lock-free to fully
   *       guarded allocator before any allocation happened.
   */
  {
    int i;
    for (i = 0; i < argc; i++) {
      if (STR_ELEM(argv[i], "-d", "--debug", "--debug-memory", "--debug-all")) {
        printf("Switching to fully guarded memory allocator.\n");
        MEM_use_guarded_allocator();
        break;
      }
      if (STR_ELEM(argv[i], "--", "-c", "--command")) {
        break;
      }
    }
    MEM_init_memleak_detection();
  }

#ifdef BUILD_DATE
  {
    const time_t temp_time = build_commit_timestamp;
    const tm *tm = gmtime(&temp_time);
    if (LIKELY(tm)) {
      strftime(build_commit_date, sizeof(build_commit_date), "%Y-%m-%d", tm);
      strftime(build_commit_time, sizeof(build_commit_time), "%H:%M", tm);
    }
    else {
      const char *unknown = "date-unknown";
      STRNCPY(build_commit_date, unknown);
      STRNCPY(build_commit_time, unknown);
    }
  }
#endif

  /* Initialize logging. */
  CLG_init();
  CLG_output_use_timestamp_set(true);
  CLG_output_use_memory_set(false);
  CLG_output_use_source_set(false);
  CLG_output_use_basename_set(false);
  CLG_fatal_fn_set(callback_clg_fatal);

  C = CTX_create();

  app_init_data_early_exit.C = C;

#ifdef WITH_PYTHON_MODULE
#  ifdef __APPLE__
  environ = *_NSGetEnviron();
#  endif

#  undef main
  main_python_evil_C = C;
#endif

#ifdef WITH_BINRELOC
  br_init(nullptr);
#endif

#ifdef WITH_LIBMV
  libmv_initLogging(argv[0]);
#endif

#if defined(WITH_TBB_MALLOC) && defined(_MSC_VER) && defined(NDEBUG) && defined(WITH_GMP)
  gmp_blender_init_allocator();
#endif

  main_callback_setup();

#if defined(__APPLE__) && !defined(BLENDER_IOS) && !defined(WITH_PYTHON_MODULE) && \
    !defined(WITH_HEADLESS)
  /* Patch to ignore argument finder gives us (PID?). */
  if (argc == 2 && STRPREFIX(argv[1], "-psn_")) {
    static char firstfilebuf[512];

    argc = 1;

    if (GHOST_HACK_getFirstFile(firstfilebuf)) {
      argc = 2;
      argv[1] = firstfilebuf;
    }
  }
#endif

#ifdef __FreeBSD__
  fpsetmask(0);
#endif

  /* Initialize path to executable. */
  BKE_appdir_program_path_init(argv[0]);

  BLI_threadapi_init();

  DNA_sdna_current_init();

  BKE_blender_globals_init(); /* `blender.cc` */

  BKE_cpp_types_init();
  fn::multi_function::register_common_functions();
  BKE_idtype_init();
  BKE_modifier_init();
  seq::modifiers_init();
  BKE_shaderfx_init();
  BKE_volumes_init();
  DEG_register_node_types();

  BKE_callback_global_init();

/* First test for background-mode (#Global.background). */
#ifndef WITH_PYTHON_MODULE
  ba = BLI_args_create(argc, argv); /* Skip binary path. */

  /* Ensure we free on early exit. */
  app_init_data.ba = ba;

  main_args_setup(C, ba, false);

  /* Parse environment handling arguments. */
  BLI_args_parse(ba, ARG_PASS_ENVIRONMENT, nullptr, nullptr);

#else
  /* Using preferences or user startup makes no sense for #WITH_PYTHON_MODULE. */
  G.factory_startup = true;
#endif

  /* After parsing #ARG_PASS_ENVIRONMENT such as `--env-*`,
   * since they impact `BKE_appdir` behavior. */
  BKE_appdir_init();

  /* After parsing number of threads argument. */
  BLI_task_scheduler_init();

  /* Initialize FFTW threading support. */
  fftw::initialize_float();

#ifndef WITH_PYTHON_MODULE
  /* The settings pass includes:
   * - Background-mode assignment (#Global.background), checked by other subsystems
   *   which may be skipped in background mode.
   * - The animation player may be launched which takes over argument passing,
   *   initializes the sub-systems it needs which have not yet been started.
   *   The animation player will call `exit(..)` too, so code after this call
   *   never runs when it's invoked.
   * - All the `--debug-*` flags.
   */
  BLI_args_parse(ba, ARG_PASS_SETTINGS, nullptr, nullptr);

  main_signal_setup();
#endif

  /* Continue with regular initialization, no need to use "early" exit. */
  app_init_data.early_exit = nullptr;

#ifdef WITH_CYCLES
  CCL_log_init();
  CCL_implicit_sharing_init();
#endif

  /* Set max open files to better handle production files that may use many
   * open geometry or texture cache file handles. After logging since it's used .*/
  BLI_system_max_open_files_ensure();

  /* Must be initialized after #BKE_appdir_init to account for color-management paths. */
  IMB_init();
  /* Keep after #ARG_PASS_SETTINGS since debug flags are checked. */
  MOV_init();

  /* After #ARG_PASS_SETTINGS arguments, this is so #WM_main_playanim skips #RNA_init. */
  RNA_init();

  RE_texture_rng_init();
  RE_engines_init();
  bke::node_system_init();

  BKE_brush_system_init();
  BKE_particle_init_rng();
  /* End second initialization. */

#if defined(WITH_PYTHON_MODULE) || defined(WITH_HEADLESS)
  /* Python module mode ALWAYS runs in background-mode (for now). */
  G.background = true;
  /* Manually using `--background` also forces the audio device. */
  BKE_sound_force_device("None");
#else
  if (G.background) {
    main_signal_setup_background();
  }
#endif

  /* Background render uses this font too. */
  BKE_vfont_builtin_register(datatoc_bfont_pfb, datatoc_bfont_pfb_size);

  /* Initialize FFMPEG if built in, also needed for background-mode if videos are
   * rendered via FFMPEG. */
  BKE_sound_init_once();

  BKE_materials_init();

#ifndef WITH_PYTHON_MODULE
  if (G.background == 0) {
    BLI_args_parse(ba, ARG_PASS_SETTINGS_GUI, nullptr, nullptr);
  }
  BLI_args_parse(ba, ARG_PASS_SETTINGS_FORCE, nullptr, nullptr);
#endif

#ifdef __ANDROID__
  __android_log_print(ANDROID_LOG_INFO, "BlenderAndroid", "calling WM_init");
#endif
  WM_init(C, argc, argv);
#ifdef __ANDROID__
  __android_log_print(ANDROID_LOG_INFO, "BlenderAndroid", "WM_init returned");
#endif

#ifndef WITH_PYTHON
  fprintf(stderr,
          "\n"
          "WARNING: Blender compiled without Python!\n"
          "This is not intended for typical usage.\n"
          "\n");
#endif

#ifdef WITH_FREESTYLE
  /* Initialize Freestyle. */
  FRS_init();
  FRS_set_context(C);
#endif

/* OK we are ready for it. */
#ifndef WITH_PYTHON_MODULE
  /* Handles #ARG_PASS_FINAL. */
  BLI_args_parse(ba, ARG_PASS_FINAL, main_args_handle_load_file, C);
#endif

  /* Explicitly free data allocated for argument parsing:
   * - `ba`
   * - `argv` on WIN32.
   */
  callback_main_atexit(&app_init_data);
  BKE_blender_atexit_unregister(callback_main_atexit, &app_init_data);

/* Paranoid, avoid accidental re-use. */
#ifndef WITH_PYTHON_MODULE
  ba = nullptr;
  (void)ba;
#endif

#ifdef USE_WIN32_UNICODE_ARGS
  argv = nullptr;
  (void)argv;
#endif

#ifndef WITH_PYTHON_MODULE
  if (G.background) {
    int exit_code;
    if (app_state.main_arg_deferred != nullptr) {
      exit_code = main_arg_deferred_handle();
      main_arg_deferred_free();
    }
    else {
      exit_code = G.is_break ? EXIT_FAILURE : EXIT_SUCCESS;
    }
    /* Using window-manager API in background-mode is a bit odd, but works fine. */
    WM_exit(C, exit_code);
  }
  else {
    /* Not supported, although it could be made to work if needed. */
    BLI_assert(app_state.main_arg_deferred == nullptr);

#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "BlenderAndroid", "before splash");
#endif
    /* Shows the splash as needed. */
    WM_init_splash_on_startup(C);
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "BlenderAndroid", "entering WM_main");
#endif

    WM_main(C);
  }
  /* Neither #WM_exit, #WM_main return, this quiets CLANG's `unreachable-code-return` warning. */
  BLI_assert_unreachable();

#endif /* !WITH_PYTHON_MODULE */

  return 0;

} /* End of `int main(...)` function. */

#if defined(__ANDROID__)
#  include <android/log.h>
#  include <csignal>
#  include <cxxabi.h>
#  include <dlfcn.h>
#  include <exception>
#  include <unistd.h>
#  include <unwind.h>

namespace {
struct BlenderUnwindState {
  int depth = 0;
};

_Unwind_Reason_Code blender_android_unwind_cb(struct _Unwind_Context *unw_ctx, void *arg)
{
  BlenderUnwindState *state = static_cast<BlenderUnwindState *>(arg);
  if (state->depth > 48) {
    return _URC_END_OF_STACK;
  }
  const uintptr_t pc = _Unwind_GetIP(unw_ctx);
  Dl_info info{};
  const bool have = (pc != 0) && dladdr(reinterpret_cast<void *>(pc), &info);
  const uintptr_t base = (have && info.dli_fbase) ? reinterpret_cast<uintptr_t>(info.dli_fbase) : 0;
  const uintptr_t rel = (base != 0 && pc >= base) ? (pc - base) : pc;
  const char *sym = (have && info.dli_sname) ? info.dli_sname : "?";
  int status = 0;
  char *demangled = (have && info.dli_sname) ?
                        abi::__cxa_demangle(info.dli_sname, nullptr, nullptr, &status) :
                        nullptr;
  __android_log_print(ANDROID_LOG_ERROR,
                      "BlenderAndroid",
                      "  #%02d pc %p rel 0x%lx %s (%s)",
                      state->depth,
                      reinterpret_cast<void *>(pc),
                      static_cast<unsigned long>(rel),
                      (have && info.dli_fname) ? info.dli_fname : "?",
                      (status == 0 && demangled) ? demangled : sym);
  std::free(demangled);
  state->depth++;
  return _URC_NO_REASON;
}

void blender_android_dump_unwind(const char *why)
{
  __android_log_print(ANDROID_LOG_ERROR, "BlenderAndroid", "%s", why);
  BlenderUnwindState state;
  _Unwind_Backtrace(blender_android_unwind_cb, &state);
}

void blender_android_terminate()
{
  blender_android_dump_unwind("std::terminate (pure virtual / uncaught)");
  std::abort();
}

void blender_android_sigabrt(int /*signum*/)
{
  static bool dumping = false;
  if (dumping) {
    _exit(1);
  }
  dumping = true;
  blender_android_dump_unwind("SIGABRT");
  _exit(1);
}
}  // namespace

/* SDLActivity.java dlsym()s an unmangled C `SDL_main` from libblender.so. */
extern "C" __attribute__((used, visibility("default"))) int SDL_main(int argc, char *argv[])
{
  std::set_terminate(blender_android_terminate);
  std::signal(SIGABRT, blender_android_sigabrt);
  /* Finger events are handled in GHOST. Do not also synthesize mouse
   * clicks from the same touches — that double-fires UI and the viewport. */
  SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
  SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
  SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
  SDL_SetMainReady();
  return main(argc, const_cast<const char **>(argv));
}
#endif

#if defined(BLENDER_IOS)
static int blender_ios_sdl_main(int argc, char *argv[])
{
  SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "1");
  SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight Portrait");
  /* SDL dlopens this. A bare "MoltenVK" name does not see the embedded framework. */
  SDL_SetHint("SDL_VULKAN_LIBRARY", "@rpath/MoltenVK.framework/MoltenVK");
  SDL_SetMainReady();
  return main(argc, const_cast<const char **>(argv));
}

/* Process main() stays in the Xcode app. SDL_RunApp starts UIKit, then this. */
extern "C" __attribute__((used, visibility("default"))) int blender_ios_main(int argc,
                                                                            char *argv[])
{
  return SDL_RunApp(argc, argv, blender_ios_sdl_main, nullptr);
}
#endif

/** \} */
