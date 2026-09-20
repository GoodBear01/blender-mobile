/* SPDX-FileCopyrightText: 2011-2023 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 */

#include <cassert>
#include <cmath>
#include <cstring>
#include <stdexcept>

#include "GHOST_ContextSDL.hh"
#ifdef WITH_VULKAN_BACKEND
#  include "GHOST_ContextVK.hh"
#endif
#include "GHOST_Mobile.hh"
#include "GHOST_SystemSDL.hh"
#include "GHOST_WindowSDL.hh"

#include "GHOST_WindowManager.hh"

#include "GHOST_EventButton.hh"
#include "GHOST_EventCursor.hh"
#include "GHOST_EventKey.hh"
#include "GHOST_EventWheel.hh"
#include "GHOST_EventTrackpad.hh"

GHOST_SystemSDL::GHOST_SystemSDL() : GHOST_System()
{
  if (!SDL_Init(SDL_INIT_VIDEO)) {
    throw std::runtime_error(SDL_GetError());
  }

  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
}

GHOST_SystemSDL::~GHOST_SystemSDL()
{
  SDL_Quit();
}

GHOST_IWindow *GHOST_SystemSDL::createWindow(const char *title,
                                             int32_t left,
                                             int32_t top,
                                             uint32_t width,
                                             uint32_t height,
                                             GHOST_TWindowState state,
                                             GHOST_GPUSettings gpu_settings,
                                             const bool exclusive,
                                             const bool /*is_dialog*/,
                                             const GHOST_IWindow *parent_window)
{
#ifdef BLENDER_MOBILE
  /* A second SDL/Vulkan window kills the single Activity surface. */
  if (window_manager_ && !window_manager_->getWindows().empty()) {
    GHOST_PRINT("Android: refusing extra window '" << (title ? title : "") << "'\n");
    return nullptr;
  }
#endif

  GHOST_WindowSDL *window = nullptr;

  const GHOST_ContextParams context_params = GHOST_CONTEXT_PARAMS_FROM_GPU_SETTINGS(gpu_settings);

  window = new GHOST_WindowSDL(this,
                               title,
                               left,
                               top,
                               width,
                               height,
                               state,
                               gpu_settings.context_type,
                               context_params,
                               exclusive,
                               parent_window);

  if (window) {
    if (GHOST_kWindowStateFullScreen == state) {
      SDL_Window *sdl_win = window->getSDLWindow();
      SDL_SetWindowFullscreenMode(sdl_win, nullptr);
      SDL_ShowWindow(sdl_win);
      SDL_SetWindowFullscreen(sdl_win, true);
    }

    if (window->getValid()) {
      window_manager_->addWindow(window);
      window_manager_->setActiveWindow(window);
      pushEvent(std::make_unique<GHOST_Event>(getMilliSeconds(), GHOST_kEventWindowSize, window));
    }
    else {
      delete window;
      window = nullptr;
    }
  }
  return window;
}

GHOST_TSuccess GHOST_SystemSDL::init()
{
  GHOST_TSuccess success = GHOST_System::init();

  if (success) {
    return GHOST_kSuccess;
  }

  return GHOST_kFailure;
}

/**
 * Returns the dimensions of the main display on this system.
 * \return The dimension of the main display.
 */
void GHOST_SystemSDL::getAllDisplayDimensions(uint32_t &width, uint32_t &height) const
{
  SDL_DisplayID display_id = SDL_GetPrimaryDisplay();
  const SDL_DisplayMode *mode = SDL_GetDesktopDisplayMode(display_id);
  if (mode == nullptr) {
    return;
  }
  width = mode->w;
  height = mode->h;
}

void GHOST_SystemSDL::getMainDisplayDimensions(uint32_t &width, uint32_t &height) const
{
  SDL_DisplayID display_id = SDL_GetPrimaryDisplay();
  const SDL_DisplayMode *mode = SDL_GetCurrentDisplayMode(display_id);
  if (mode == nullptr) {
    return;
  }
  width = mode->w;
  height = mode->h;
}

uint8_t GHOST_SystemSDL::getNumDisplays() const
{
  int count = 0;
  SDL_DisplayID *displays = SDL_GetDisplays(&count);
  SDL_free(displays);
  return uint8_t(count);
}

GHOST_IContext *GHOST_SystemSDL::createOffscreenContext(GHOST_GPUSettings gpu_settings)
{
  const GHOST_ContextParams context_params_offscreen =
      GHOST_CONTEXT_PARAMS_FROM_GPU_SETTINGS_OFFSCREEN(gpu_settings);

  switch (gpu_settings.context_type) {
#ifdef WITH_OPENGL_BACKEND
    case GHOST_kDrawingContextTypeOpenGL: {
      for (int minor = 6; minor >= 3; --minor) {
        GHOST_Context *context = new GHOST_ContextSDL(
            context_params_offscreen,
            nullptr,
            0, /* Profile bit. */
            4,
            minor,
            GHOST_OPENGL_SDL_CONTEXT_FLAGS,
            GHOST_OPENGL_SDL_RESET_NOTIFICATION_STRATEGY);

        if (context->initializeDrawingContext()) {
          return context;
        }
        delete context;
      }
      return nullptr;
    }
#endif

#ifdef WITH_VULKAN_BACKEND
    case GHOST_kDrawingContextTypeVulkan: {
      GHOST_Context *context = new GHOST_ContextVK(context_params_offscreen,
#ifndef _WIN32
#  ifndef __APPLE__
                                                   GHOST_kVulkanPlatformHeadless,
                                                   0,
                                                   nullptr,
                                                   nullptr,
                                                   nullptr,
                                                   nullptr,
#  endif
#endif
                                                   1,
                                                   2,
                                                   gpu_settings.preferred_device);
      if (context->initializeDrawingContext()) {
        return context;
      }
      delete context;
      return nullptr;
    }
#endif

    default:
      /* Unsupported backend. */
      return nullptr;
  }
}

GHOST_TSuccess GHOST_SystemSDL::disposeContext(GHOST_IContext *context)
{
  delete context;

  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemSDL::getModifierKeys(GHOST_ModifierKeys &keys) const
{
  SDL_Keymod mod = SDL_GetModState();

  keys.set(GHOST_kModifierKeyLeftShift, (mod & SDL_KMOD_LSHIFT) != 0);
  keys.set(GHOST_kModifierKeyRightShift, (mod & SDL_KMOD_RSHIFT) != 0);
  keys.set(GHOST_kModifierKeyLeftControl, (mod & SDL_KMOD_LCTRL) != 0);
  keys.set(GHOST_kModifierKeyRightControl, (mod & SDL_KMOD_RCTRL) != 0);
  keys.set(GHOST_kModifierKeyLeftAlt, (mod & SDL_KMOD_LALT) != 0);
  keys.set(GHOST_kModifierKeyRightAlt, (mod & SDL_KMOD_RALT) != 0);
  keys.set(GHOST_kModifierKeyLeftOS, (mod & SDL_KMOD_LGUI) != 0);
  keys.set(GHOST_kModifierKeyRightOS, (mod & SDL_KMOD_RGUI) != 0);

  return GHOST_kSuccess;
}

#define GXMAP(k, x, y) \
  case x: \
    k = y; \
    break

static GHOST_TKey convertSDLKey(SDL_Scancode key)
{
  GHOST_TKey type;

  if ((key >= SDL_SCANCODE_A) && (key <= SDL_SCANCODE_Z)) {
    type = GHOST_TKey(key - SDL_SCANCODE_A + int(GHOST_kKeyA));
  }
  else if ((key >= SDL_SCANCODE_1) && (key <= SDL_SCANCODE_0)) {
    type = (key == SDL_SCANCODE_0) ? GHOST_kKey0 :
                                     GHOST_TKey(key - SDL_SCANCODE_1 + int(GHOST_kKey1));
  }
  else if ((key >= SDL_SCANCODE_F1) && (key <= SDL_SCANCODE_F12)) {
    type = GHOST_TKey(key - SDL_SCANCODE_F1 + int(GHOST_kKeyF1));
  }
  else if ((key >= SDL_SCANCODE_F13) && (key <= SDL_SCANCODE_F24)) {
    type = GHOST_TKey(key - SDL_SCANCODE_F13 + int(GHOST_kKeyF13));
  }
  else {
    switch (key) {
      GXMAP(type, SDL_SCANCODE_BACKSPACE, GHOST_kKeyBackSpace);
      GXMAP(type, SDL_SCANCODE_TAB, GHOST_kKeyTab);
      GXMAP(type, SDL_SCANCODE_RETURN, GHOST_kKeyEnter);
      GXMAP(type, SDL_SCANCODE_ESCAPE, GHOST_kKeyEsc);
      GXMAP(type, SDL_SCANCODE_SPACE, GHOST_kKeySpace);

      GXMAP(type, SDL_SCANCODE_SEMICOLON, GHOST_kKeySemicolon);
      GXMAP(type, SDL_SCANCODE_PERIOD, GHOST_kKeyPeriod);
      GXMAP(type, SDL_SCANCODE_COMMA, GHOST_kKeyComma);
      GXMAP(type, SDL_SCANCODE_APOSTROPHE, GHOST_kKeyQuote);
      GXMAP(type, SDL_SCANCODE_GRAVE, GHOST_kKeyAccentGrave);
      GXMAP(type, SDL_SCANCODE_MINUS, GHOST_kKeyMinus);
      GXMAP(type, SDL_SCANCODE_EQUALS, GHOST_kKeyEqual);

      GXMAP(type, SDL_SCANCODE_SLASH, GHOST_kKeySlash);
      GXMAP(type, SDL_SCANCODE_BACKSLASH, GHOST_kKeyBackslash);
      GXMAP(type, SDL_SCANCODE_KP_EQUALS, GHOST_kKeyEqual);
      GXMAP(type, SDL_SCANCODE_LEFTBRACKET, GHOST_kKeyLeftBracket);
      GXMAP(type, SDL_SCANCODE_RIGHTBRACKET, GHOST_kKeyRightBracket);
      GXMAP(type, SDL_SCANCODE_PAUSE, GHOST_kKeyPause);

      GXMAP(type, SDL_SCANCODE_LSHIFT, GHOST_kKeyLeftShift);
      GXMAP(type, SDL_SCANCODE_RSHIFT, GHOST_kKeyRightShift);
      GXMAP(type, SDL_SCANCODE_LCTRL, GHOST_kKeyLeftControl);
      GXMAP(type, SDL_SCANCODE_RCTRL, GHOST_kKeyRightControl);
      GXMAP(type, SDL_SCANCODE_LALT, GHOST_kKeyLeftAlt);
      GXMAP(type, SDL_SCANCODE_RALT, GHOST_kKeyRightAlt);
      GXMAP(type, SDL_SCANCODE_LGUI, GHOST_kKeyLeftOS);
      GXMAP(type, SDL_SCANCODE_RGUI, GHOST_kKeyRightOS);
      GXMAP(type, SDL_SCANCODE_APPLICATION, GHOST_kKeyApp);

      GXMAP(type, SDL_SCANCODE_INSERT, GHOST_kKeyInsert);
      GXMAP(type, SDL_SCANCODE_DELETE, GHOST_kKeyDelete);
      GXMAP(type, SDL_SCANCODE_HOME, GHOST_kKeyHome);
      GXMAP(type, SDL_SCANCODE_END, GHOST_kKeyEnd);
      GXMAP(type, SDL_SCANCODE_PAGEUP, GHOST_kKeyUpPage);
      GXMAP(type, SDL_SCANCODE_PAGEDOWN, GHOST_kKeyDownPage);

      GXMAP(type, SDL_SCANCODE_LEFT, GHOST_kKeyLeftArrow);
      GXMAP(type, SDL_SCANCODE_RIGHT, GHOST_kKeyRightArrow);
      GXMAP(type, SDL_SCANCODE_UP, GHOST_kKeyUpArrow);
      GXMAP(type, SDL_SCANCODE_DOWN, GHOST_kKeyDownArrow);

      GXMAP(type, SDL_SCANCODE_CAPSLOCK, GHOST_kKeyCapsLock);
      GXMAP(type, SDL_SCANCODE_SCROLLLOCK, GHOST_kKeyScrollLock);
      GXMAP(type, SDL_SCANCODE_NUMLOCKCLEAR, GHOST_kKeyNumLock);
      GXMAP(type, SDL_SCANCODE_PRINTSCREEN, GHOST_kKeyPrintScreen);

      /* keypad events */

      /* NOTE: SDL defines a bunch of key-pad identifiers that aren't supported by GHOST,
       * such as #SDL_SCANCODE_KP_PERCENT, #SDL_SCANCODE_KP_XOR. */
      GXMAP(type, SDL_SCANCODE_KP_0, GHOST_kKeyNumpad0);
      GXMAP(type, SDL_SCANCODE_KP_1, GHOST_kKeyNumpad1);
      GXMAP(type, SDL_SCANCODE_KP_2, GHOST_kKeyNumpad2);
      GXMAP(type, SDL_SCANCODE_KP_3, GHOST_kKeyNumpad3);
      GXMAP(type, SDL_SCANCODE_KP_4, GHOST_kKeyNumpad4);
      GXMAP(type, SDL_SCANCODE_KP_5, GHOST_kKeyNumpad5);
      GXMAP(type, SDL_SCANCODE_KP_6, GHOST_kKeyNumpad6);
      GXMAP(type, SDL_SCANCODE_KP_7, GHOST_kKeyNumpad7);
      GXMAP(type, SDL_SCANCODE_KP_8, GHOST_kKeyNumpad8);
      GXMAP(type, SDL_SCANCODE_KP_9, GHOST_kKeyNumpad9);
      GXMAP(type, SDL_SCANCODE_KP_PERIOD, GHOST_kKeyNumpadPeriod);

      GXMAP(type, SDL_SCANCODE_KP_ENTER, GHOST_kKeyNumpadEnter);
      GXMAP(type, SDL_SCANCODE_KP_PLUS, GHOST_kKeyNumpadPlus);
      GXMAP(type, SDL_SCANCODE_KP_MINUS, GHOST_kKeyNumpadMinus);
      GXMAP(type, SDL_SCANCODE_KP_MULTIPLY, GHOST_kKeyNumpadAsterisk);
      GXMAP(type, SDL_SCANCODE_KP_DIVIDE, GHOST_kKeyNumpadSlash);

      /* Media keys in some keyboards and laptops with XFree86/XORG. */
      GXMAP(type, SDL_SCANCODE_MEDIA_PLAY, GHOST_kKeyMediaPlay);
      GXMAP(type, SDL_SCANCODE_MEDIA_STOP, GHOST_kKeyMediaStop);
      GXMAP(type, SDL_SCANCODE_MEDIA_PREVIOUS_TRACK, GHOST_kKeyMediaFirst);
      GXMAP(type, SDL_SCANCODE_MEDIA_NEXT_TRACK, GHOST_kKeyMediaLast);

      /* International Keys. */

      /* This key has multiple purposes,
       * however the only GHOST key that uses the scan-code is GrLess. */
      GXMAP(type, SDL_SCANCODE_NONUSBACKSLASH, GHOST_kKeyGrLess);

      default:
        printf("Unknown\n");
        type = GHOST_kKeyUnknown;
        break;
    }
  }

  return type;
}
#undef GXMAP

static char convert_keyboard_event_to_ascii(const SDL_KeyboardEvent &sdl_sub_evt)
{
  SDL_Keycode sym = sdl_sub_evt.key;
  if (sym > 127) {
    switch (sym) {
      case SDLK_KP_DIVIDE:
        sym = '/';
        break;
      case SDLK_KP_MULTIPLY:
        sym = '*';
        break;
      case SDLK_KP_MINUS:
        sym = '-';
        break;
      case SDLK_KP_PLUS:
        sym = '+';
        break;
      case SDLK_KP_1:
        sym = '1';
        break;
      case SDLK_KP_2:
        sym = '2';
        break;
      case SDLK_KP_3:
        sym = '3';
        break;
      case SDLK_KP_4:
        sym = '4';
        break;
      case SDLK_KP_5:
        sym = '5';
        break;
      case SDLK_KP_6:
        sym = '6';
        break;
      case SDLK_KP_7:
        sym = '7';
        break;
      case SDLK_KP_8:
        sym = '8';
        break;
      case SDLK_KP_9:
        sym = '9';
        break;
      case SDLK_KP_0:
        sym = '0';
        break;
      case SDLK_KP_PERIOD:
        sym = '.';
        break;
      default:
        sym = 0;
        break;
    }
  }
  else {
    if (sdl_sub_evt.mod & (SDL_KMOD_LSHIFT | SDL_KMOD_RSHIFT)) {
      /* Weak US keyboard assumptions. */
      if (sym >= 'a' && sym <= ('a' + 32)) {
        sym -= 32;
      }
      else {
        switch (sym) {
          case '`':
            sym = '~';
            break;
          case '1':
            sym = '!';
            break;
          case '2':
            sym = '@';
            break;
          case '3':
            sym = '#';
            break;
          case '4':
            sym = '$';
            break;
          case '5':
            sym = '%';
            break;
          case '6':
            sym = '^';
            break;
          case '7':
            sym = '&';
            break;
          case '8':
            sym = '*';
            break;
          case '9':
            sym = '(';
            break;
          case '0':
            sym = ')';
            break;
          case '-':
            sym = '_';
            break;
          case '=':
            sym = '+';
            break;
          case '[':
            sym = '{';
            break;
          case ']':
            sym = '}';
            break;
          case '\\':
            sym = '|';
            break;
          case ';':
            sym = ':';
            break;
          case '\'':
            sym = '"';
            break;
          case ',':
            sym = '<';
            break;
          case '.':
            sym = '>';
            break;
          case '/':
            sym = '?';
            break;
          default:
            break;
        }
      }
    }
  }
  return char(sym);
}

/**
 * Events don't always have valid windows,
 * but GHOST needs a window _always_. Fall back to the GL window.
 */
static SDL_Window *SDL_GetWindowFromID_fallback(SDL_WindowID id)
{
  SDL_Window *sdl_win = SDL_GetWindowFromID(id);
  if (sdl_win == nullptr) {
    sdl_win = SDL_GL_GetCurrentWindow();
  }
  return sdl_win;
}

static void finger_to_root(SDL_Window *sdl_win, float norm_x, float norm_y, int32_t &x_root, int32_t &y_root)
{
  /* Must match #GHOST_WindowSDL::getClientBounds (SDL_GetWindowSize), not the
   * pixel drawable size. Otherwise high-DPI phones map touches off the 3D view. */
  int win_w = 0, win_h = 0;
  SDL_GetWindowSize(sdl_win, &win_w, &win_h);
  int x_win = 0, y_win = 0;
  SDL_GetWindowPosition(sdl_win, &x_win, &y_win);
  x_root = int32_t(norm_x * float(win_w)) + x_win;
  y_root = int32_t(norm_y * float(win_h)) + y_win;
}

static void client_to_root(SDL_Window *sdl_win, float x_client, float y_client, int32_t &x_root, int32_t &y_root)
{
  int x_win = 0, y_win = 0;
  SDL_GetWindowPosition(sdl_win, &x_win, &y_win);
  x_root = int32_t(x_client) + x_win;
  y_root = int32_t(y_client) + y_win;
}

void GHOST_SystemSDL::touchResetState()
{
  for (TouchFingerState &finger : touch_fingers_) {
    finger.active = false;
    finger.finger_id = 0;
  }
  active_touch_count_ = 0;
  touch_mode_ = TOUCH_MODE_NONE;
  touch_pinch_active_ = false;
  touch_using_fingers_ = false;
  touch_middle_down_ = false;
  touch_left_down_ = false;
  touch_right_down_ = false;
  touch_shift_down_ = false;
  touch_pinch_dist_ = -1.0f;
  touch_start_x_ = 0;
  touch_start_y_ = 0;
  touch_last_x_ = 0;
  touch_last_y_ = 0;
}

void GHOST_SystemSDL::touchUpdateFinger(const SDL_FingerID finger_id,
                                        const float x,
                                        const float y,
                                        const bool active)
{
  int free_slot = -1;
  for (int i = 0; i < kMaxTouchFingers; i++) {
    if (touch_fingers_[i].active && touch_fingers_[i].finger_id == finger_id) {
      touch_fingers_[i].x = x;
      touch_fingers_[i].y = y;
      touch_fingers_[i].active = active;
      if (!active) {
        touch_fingers_[i].finger_id = 0;
      }
      return;
    }
    if (!touch_fingers_[i].active && free_slot == -1) {
      free_slot = i;
    }
  }
  if (active && free_slot != -1) {
    touch_fingers_[free_slot].finger_id = finger_id;
    touch_fingers_[free_slot].x = x;
    touch_fingers_[free_slot].y = y;
    touch_fingers_[free_slot].active = true;
  }
}

int GHOST_SystemSDL::touchCountActiveFingers() const
{
  int count = 0;
  for (const TouchFingerState &finger : touch_fingers_) {
    if (finger.active) {
      count += 1;
    }
  }
  return count;
}

void GHOST_SystemSDL::touchGetCentroid(float &x_out, float &y_out) const
{
  float sum_x = 0.0f;
  float sum_y = 0.0f;
  int count = 0;
  for (const TouchFingerState &finger : touch_fingers_) {
    if (finger.active) {
      sum_x += finger.x;
      sum_y += finger.y;
      count += 1;
    }
  }
  if (count == 0) {
    x_out = 0.5f;
    y_out = 0.5f;
    return;
  }
  x_out = sum_x / float(count);
  y_out = sum_y / float(count);
}

float GHOST_SystemSDL::touchFingerSpread() const
{
  float pts[2][2];
  int count = 0;
  for (const TouchFingerState &finger : touch_fingers_) {
    if (!finger.active) {
      continue;
    }
    if (count < 2) {
      pts[count][0] = finger.x;
      pts[count][1] = finger.y;
    }
    count += 1;
    if (count == 2) {
      break;
    }
  }
  if (count < 2) {
    return -1.0f;
  }
  const float dx = pts[0][0] - pts[1][0];
  const float dy = pts[0][1] - pts[1][1];
  return sqrtf(dx * dx + dy * dy);
}

GHOST_WindowSDL *GHOST_SystemSDL::findGhostWindowOrPrimary(SDL_Window *sdl_win)
{
  GHOST_WindowSDL *window = findGhostWindow(sdl_win);
  if (window != nullptr) {
    return window;
  }
  const std::vector<GHOST_IWindow *> &win_vec = window_manager_->getWindows();
  if (!win_vec.empty()) {
    return static_cast<GHOST_WindowSDL *>(win_vec[0]);
  }
  return nullptr;
}

bool GHOST_SystemSDL::processAndroidTouchAt(const uint64_t event_ms,
                                            GHOST_WindowSDL *window,
                                            const int32_t x_root,
                                            const int32_t y_root,
                                            const TouchPointerPhase phase)
{
  if (window == nullptr) {
    return false;
  }

  auto push_cursor = [&]() {
    pushEvent(std::make_unique<GHOST_EventCursor>(
        event_ms, GHOST_kEventCursorMove, window, x_root, y_root, GHOST_TABLET_DATA_NONE));
  };
  auto push_button = [&](const GHOST_TEventType type, const GHOST_TButton button) {
    pushEvent(std::make_unique<GHOST_EventButton>(
        event_ms, type, window, button, GHOST_TABLET_DATA_NONE));
  };
  auto ensure_left_down = [&]() {
    if (!touch_left_down_) {
      push_cursor();
      push_button(GHOST_kEventButtonDown, GHOST_kButtonMaskLeft);
      touch_left_down_ = true;
    }
  };
  auto release_left = [&]() {
    if (touch_left_down_) {
      push_button(GHOST_kEventButtonUp, GHOST_kButtonMaskLeft);
      touch_left_down_ = false;
    }
  };
  auto release_middle = [&]() {
    if (touch_middle_down_) {
      push_button(GHOST_kEventButtonUp, GHOST_kButtonMaskMiddle);
      touch_middle_down_ = false;
    }
  };
  auto release_right = [&]() {
    if (touch_right_down_) {
      push_button(GHOST_kEventButtonUp, GHOST_kButtonMaskRight);
      touch_right_down_ = false;
    }
  };
  auto release_shift = [&]() {
    if (touch_shift_down_) {
      pushEvent(std::make_unique<GHOST_EventKey>(
          event_ms, GHOST_kEventKeyUp, window, GHOST_kKeyLeftShift, false));
      touch_shift_down_ = false;
    }
  };
  auto release_all_buttons = [&]() {
    release_middle();
    release_left();
    release_right();
    release_shift();
  };

  if (phase == TOUCH_POINTER_DOWN) {
    active_touch_count_ += 1;
    if (active_touch_count_ == 1 && !touch_pinch_active_) {
      touch_mode_ = TOUCH_MODE_PENDING_TAP;
      touch_start_x_ = x_root;
      touch_start_y_ = y_root;
      touch_last_x_ = x_root;
      touch_last_y_ = y_root;
      touch_pinch_dist_ = -1.0f;
      /* Press immediately so the 3D navigate/transform gizmos receive the
       * click on the icon, not 16px later after the finger has left it. */
      push_cursor();
      ensure_left_down();
    }
    else if (active_touch_count_ >= 2) {
      /* Second finger: stop orbit. Pan via trackpad, not RMB (real right-click). */
      release_all_buttons();
      touch_mode_ = TOUCH_MODE_MULTI;
      touch_pinch_dist_ = touchFingerSpread();
      if (SDL_Window *sdl_win = window->getSDLWindow()) {
        float cx = 0.5f, cy = 0.5f;
        touchGetCentroid(cx, cy);
        finger_to_root(sdl_win, cx, cy, touch_last_x_, touch_last_y_);
      }
    }
    return true;
  }

  if (phase == TOUCH_POINTER_MOVE) {
    if (active_touch_count_ >= 2 || touch_mode_ == TOUCH_MODE_MULTI || touch_pinch_active_) {
      touch_mode_ = TOUCH_MODE_MULTI;
      release_left();
      release_middle();
      release_shift();
      const float spread = touchFingerSpread();
      float ds = 0.0f;
      if (spread > 0.0f) {
        if (touch_pinch_dist_ > 0.0f) {
          ds = spread - touch_pinch_dist_;
        }
        touch_pinch_dist_ = spread;
      }
      if (fabsf(ds) >= 0.012f) {
        const int magnify = int(ds * 90.0f);
        if (magnify != 0) {
          pushEvent(std::make_unique<GHOST_EventWheel>(
              event_ms, window, GHOST_kEventWheelAxisVertical, magnify > 0 ? 1 : -1));
        }
      }
      else if (SDL_Window *sdl_win = window->getSDLWindow()) {
        float cx = 0.5f, cy = 0.5f;
        touchGetCentroid(cx, cy);
        int32_t cx_root = x_root;
        int32_t cy_root = y_root;
        finger_to_root(sdl_win, cx, cy, cx_root, cy_root);
        const int32_t dx = cx_root - touch_last_x_;
        const int32_t dy = cy_root - touch_last_y_;
        if (dx != 0 || dy != 0) {
          pushEvent(std::make_unique<GHOST_EventTrackpad>(event_ms,
                                                          window,
                                                          GHOST_kTrackpadEventScroll,
                                                          cx_root,
                                                          cy_root,
                                                          dx,
                                                          dy,
                                                          false));
        }
        touch_last_x_ = cx_root;
        touch_last_y_ = cy_root;
      }
    }
    else if (active_touch_count_ == 1) {
      const float sdx = float(x_root - touch_start_x_);
      const float sdy = float(y_root - touch_start_y_);
      const float dist_sq = sdx * sdx + sdy * sdy;

      if (touch_mode_ == TOUCH_MODE_PENDING_TAP &&
          dist_sq >= kTouchDragThresholdPx * kTouchDragThresholdPx)
      {
        touch_mode_ = TOUCH_MODE_ORBIT;
        ensure_left_down();
      }
      push_cursor();
    }
    touch_last_x_ = x_root;
    touch_last_y_ = y_root;
    return true;
  }

  if (phase == TOUCH_POINTER_UP) {
    if (active_touch_count_ > 0) {
      active_touch_count_ -= 1;
    }
    if (active_touch_count_ == 0) {
      release_all_buttons();
      touchResetState();
    }
    else if (active_touch_count_ == 1) {
      release_all_buttons();
      touch_pinch_dist_ = -1.0f;
      touch_mode_ = TOUCH_MODE_PENDING_TAP;
      touch_start_x_ = x_root;
      touch_start_y_ = y_root;
      touch_last_x_ = x_root;
      touch_last_y_ = y_root;
    }
    return true;
  }

  return false;
}

void GHOST_SystemSDL::processEvent(SDL_Event *sdl_event)
{
  std::unique_ptr<GHOST_Event> g_event = nullptr;

  switch (sdl_event->type) {
#ifdef BLENDER_MOBILE
    case SDL_EVENT_WILL_ENTER_BACKGROUND:
    case SDL_EVENT_DID_ENTER_FOREGROUND: {
      const bool restore = (sdl_event->type == SDL_EVENT_DID_ENTER_FOREGROUND);
      const uint64_t event_ms = SDL_NS_TO_MS(sdl_event->common.timestamp);
      for (GHOST_IWindow *iwin : window_manager_->getWindows()) {
        GHOST_WindowSDL *window = static_cast<GHOST_WindowSDL *>(iwin);
        if (window == nullptr || window->getContext() == nullptr) {
          continue;
        }
        window->updateDrawingContext();
        if (restore) {
          pushEvent(std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowSize, window));
          pushEvent(std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowUpdate, window));
        }
      }
      break;
    }
#endif
    case SDL_EVENT_WINDOW_EXPOSED:
    case SDL_EVENT_WINDOW_SHOWN:
    case SDL_EVENT_WINDOW_HIDDEN:
    case SDL_EVENT_WINDOW_RESIZED:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
    case SDL_EVENT_WINDOW_MOVED:
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
    case SDL_EVENT_WINDOW_FOCUS_LOST:
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
    case SDL_EVENT_WINDOW_MINIMIZED:
    case SDL_EVENT_WINDOW_RESTORED: {
      const SDL_WindowEvent &sdl_sub_evt = sdl_event->window;
      const uint64_t event_ms = SDL_NS_TO_MS(sdl_sub_evt.timestamp);
      GHOST_WindowSDL *window = findGhostWindow(
          SDL_GetWindowFromID_fallback(sdl_sub_evt.windowID));
      /* Can be nullptr on close window. */

      switch (sdl_event->type) {
        case SDL_EVENT_WINDOW_EXPOSED:
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowUpdate, window);
          break;
        case SDL_EVENT_WINDOW_RESIZED:
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowSize, window);
          break;
        case SDL_EVENT_WINDOW_MOVED:
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowMove, window);
          break;
        case SDL_EVENT_WINDOW_FOCUS_GAINED:
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowActivate, window);
          break;
        case SDL_EVENT_WINDOW_FOCUS_LOST:
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowDeactivate, window);
          break;
        case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowClose, window);
          break;
        case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowSize, window);
          break;
        case SDL_EVENT_WINDOW_HIDDEN:
        case SDL_EVENT_WINDOW_MINIMIZED:
#ifdef BLENDER_MOBILE
          if (window != nullptr && window->getContext() != nullptr) {
            window->updateDrawingContext();
          }
#endif
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowDeactivate, window);
          break;
        case SDL_EVENT_WINDOW_SHOWN:
        case SDL_EVENT_WINDOW_RESTORED:
#ifdef BLENDER_MOBILE
          if (window != nullptr && window->getContext() != nullptr) {
            window->updateDrawingContext();
          }
#endif
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowActivate, window);
          if (g_event) {
            pushEvent(std::move(g_event));
          }
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowSize, window);
          if (g_event) {
            pushEvent(std::move(g_event));
          }
          g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowUpdate, window);
          break;
      }

      break;
    }

    case SDL_EVENT_QUIT: {
      const SDL_QuitEvent &sdl_sub_evt = sdl_event->quit;
      const uint64_t event_ms = SDL_NS_TO_MS(sdl_sub_evt.timestamp);
      GHOST_IWindow *window = window_manager_->getActiveWindow();
      g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventQuitRequest, window);
      break;
    }

    case SDL_EVENT_MOUSE_MOTION: {
      const SDL_MouseMotionEvent &sdl_sub_evt = sdl_event->motion;
      const uint64_t event_ms = SDL_NS_TO_MS(sdl_sub_evt.timestamp);
      SDL_Window *sdl_win = SDL_GetWindowFromID_fallback(sdl_sub_evt.windowID);
      GHOST_WindowSDL *window = findGhostWindowOrPrimary(sdl_win);
      if (window == nullptr) {
        break;
      }

      int32_t x_root = 0;
      int32_t y_root = 0;
      client_to_root(sdl_win, sdl_sub_evt.x, sdl_sub_evt.y, x_root, y_root);
#ifdef BLENDER_MOBILE
      /* Finger events already updated the view; ignore the synthetic mouse copy. */
      if (touch_using_fingers_) {
        break;
      }
      /* Bluetooth mice use a real device id, not SDL_TOUCH_MOUSEID. While a
       * left-button remap session is active, keep feeding it motion so LMB-drag
       * becomes middle-mouse orbit. */
      if (active_touch_count_ > 0 || touch_middle_down_ || touch_mode_ != TOUCH_MODE_NONE) {
        if (processAndroidTouchAt(event_ms, window, x_root, y_root, TOUCH_POINTER_MOVE)) {
          break;
        }
      }
#endif

#if 0
      if (window->getCursorGrabMode() != GHOST_kGrabDisable &&
          window->getCursorGrabMode() != GHOST_kGrabNormal)
      {
        int32_t x_new = x_root;
        int32_t y_new = y_root;
        int32_t x_accum, y_accum;
        GHOST_Rect bounds;

        /* fallback to window bounds */
        if (window->getCursorGrabBounds(bounds) == GHOST_kFailure) {
          window->getClientBounds(bounds);
        }

        /* Could also clamp to screen bounds wrap with a window outside the view will
         * fail at the moment. Use offset of 8 in case the window is at screen bounds. */
        bounds.wrapPoint(x_new, y_new, 8, window->getCursorGrabAxis());
        window->getCursorGrabAccum(x_accum, y_accum);

        /* Can't use #setCursorPosition because the mouse may have no focus! */
        if (x_new != x_root || y_new != y_root) {
          if (1 /* `xme.time > last_warp_` */) {
            /* when wrapping we don't need to add an event because the
             * #setCursorPosition call will cause a new event after */
            SDL_WarpMouseInWindow(sdl_win, x_new - x_win, y_new - y_win); /* wrap */
            window->setCursorGrabAccum(x_accum + (x_root - x_new), y_accum + (y_root - y_new));
            // last_warp_ = lastEventTime(xme.time);
          }
          else {
            // setCursorPosition(x_new, y_new); /* wrap but don't accumulate */
            SDL_WarpMouseInWindow(sdl_win, x_new - x_win, y_new - y_win);
          }

          g_event = std::make_unique<GHOST_EventCursor>(
              event_ms, GHOST_kEventCursorMove, window, x_new, y_new, GHOST_TABLET_DATA_NONE);
        }
        else {
          g_event = std::make_unique<GHOST_EventCursor>(event_ms,
                                          GHOST_kEventCursorMove,
                                          window,
                                          x_root + x_accum,
                                          y_root + y_accum,
                                          GHOST_TABLET_DATA_NONE);
        }
      }
      else
#endif
      {
        g_event = std::make_unique<GHOST_EventCursor>(
            event_ms, GHOST_kEventCursorMove, window, x_root, y_root, GHOST_TABLET_DATA_NONE);
      }
      break;
    }
    case SDL_EVENT_MOUSE_BUTTON_UP:
    case SDL_EVENT_MOUSE_BUTTON_DOWN: {
      const SDL_MouseButtonEvent &sdl_sub_evt = sdl_event->button;
      const uint64_t event_ms = SDL_NS_TO_MS(sdl_sub_evt.timestamp);
      GHOST_TButton gbmask = GHOST_kButtonMaskLeft;
      GHOST_TEventType type = sdl_sub_evt.down ? GHOST_kEventButtonDown : GHOST_kEventButtonUp;

      GHOST_WindowSDL *window = findGhostWindowOrPrimary(
          SDL_GetWindowFromID_fallback(sdl_sub_evt.windowID));
      if (window == nullptr) {
        break;
      }

#ifdef BLENDER_MOBILE
      if (touch_using_fingers_) {
        break;
      }
      /* Phone + Bluetooth mouse: tap = left click (UI/select), drag = MMB orbit. */
      if (sdl_sub_evt.button == SDL_BUTTON_LEFT) {
        SDL_Window *sdl_win = window->getSDLWindow();
        if (sdl_win != nullptr) {
          int32_t x_root = 0;
          int32_t y_root = 0;
          client_to_root(sdl_win, sdl_sub_evt.x, sdl_sub_evt.y, x_root, y_root);
          const TouchPointerPhase phase = sdl_sub_evt.down ? TOUCH_POINTER_DOWN : TOUCH_POINTER_UP;
          if (processAndroidTouchAt(event_ms, window, x_root, y_root, phase)) {
            break;
          }
        }
      }
#endif

      /* process rest of normal mouse buttons */
      if (sdl_sub_evt.button == SDL_BUTTON_LEFT) {
        gbmask = GHOST_kButtonMaskLeft;
      }
      else if (sdl_sub_evt.button == SDL_BUTTON_MIDDLE) {
        gbmask = GHOST_kButtonMaskMiddle;
      }
      else if (sdl_sub_evt.button == SDL_BUTTON_RIGHT) {
        gbmask = GHOST_kButtonMaskRight;
        /* these buttons are untested! */
      }
      else if (sdl_sub_evt.button == SDL_BUTTON_X1) {
        gbmask = GHOST_kButtonMaskButton4;
      }
      else if (sdl_sub_evt.button == SDL_BUTTON_X2) {
        gbmask = GHOST_kButtonMaskButton5;
      }
      else {
        break;
      }

      g_event = std::make_unique<GHOST_EventButton>(
          event_ms, type, window, gbmask, GHOST_TABLET_DATA_NONE);
      break;
    }
    case SDL_EVENT_MOUSE_WHEEL: {
      const SDL_MouseWheelEvent &sdl_sub_evt = sdl_event->wheel;
      const uint64_t event_ms = SDL_NS_TO_MS(sdl_sub_evt.timestamp);
      GHOST_WindowSDL *window = findGhostWindowOrPrimary(
          SDL_GetWindowFromID_fallback(sdl_sub_evt.windowID));
      if (window == nullptr) {
        break;
      }
      if (sdl_sub_evt.x != 0.0f) {
        g_event = std::make_unique<GHOST_EventWheel>(
            event_ms, window, GHOST_kEventWheelAxisHorizontal, int(sdl_sub_evt.x));
      }
      else if (sdl_sub_evt.y != 0.0f) {
        g_event = std::make_unique<GHOST_EventWheel>(
            event_ms, window, GHOST_kEventWheelAxisVertical, int(sdl_sub_evt.y));
      }
      break;
    }
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP: {
      const SDL_KeyboardEvent &sdl_sub_evt = sdl_event->key;
      const uint64_t event_ms = SDL_NS_TO_MS(sdl_sub_evt.timestamp);
      GHOST_TEventType type = sdl_sub_evt.down ? GHOST_kEventKeyDown : GHOST_kEventKeyUp;
      const bool is_repeat = sdl_sub_evt.repeat != 0;

      GHOST_WindowSDL *window = findGhostWindow(
          SDL_GetWindowFromID_fallback(sdl_sub_evt.windowID));
      assert(window != nullptr);

      GHOST_TKey gkey = convertSDLKey(sdl_sub_evt.scancode);
      /* NOTE: the `sdl_sub_evt.key` is truncated,
       * for unicode support ghost has to be modified. */

      /* TODO(@ideasman42): support full unicode, SDL supports this but it needs to be
       * explicitly enabled via #SDL_StartTextInput which GHOST would have to wrap. */
      char utf8_buf[sizeof(GHOST_TEventKeyData::utf8_buf)] = {'\0'};
      if (type == GHOST_kEventKeyDown) {
        utf8_buf[0] = convert_keyboard_event_to_ascii(sdl_sub_evt);
      }

      g_event = std::make_unique<GHOST_EventKey>(
          event_ms, type, window, gkey, is_repeat, utf8_buf);
      break;
    }
    case SDL_EVENT_FINGER_DOWN:
    case SDL_EVENT_FINGER_MOTION:
    case SDL_EVENT_FINGER_UP:
    case SDL_EVENT_FINGER_CANCELED: {
      const SDL_TouchFingerEvent &finger = sdl_event->tfinger;
      const uint64_t event_ms = SDL_NS_TO_MS(finger.timestamp);
      GHOST_WindowSDL *window = findGhostWindowOrPrimary(
          SDL_GetWindowFromID_fallback(finger.windowID));
      if (window == nullptr) {
        break;
      }
      SDL_Window *sdl_win = window->getSDLWindow();
      if (sdl_win == nullptr) {
        break;
      }

      int32_t x_root = 0;
      int32_t y_root = 0;
      finger_to_root(sdl_win, finger.x, finger.y, x_root, y_root);

      const bool finger_down = sdl_event->type == SDL_EVENT_FINGER_DOWN;
      const bool finger_up = sdl_event->type == SDL_EVENT_FINGER_UP ||
                             sdl_event->type == SDL_EVENT_FINGER_CANCELED;
      const bool finger_motion = sdl_event->type == SDL_EVENT_FINGER_MOTION;

      if (finger_down) {
        touchUpdateFinger(finger.fingerID, finger.x, finger.y, true);
      }
      else if (finger_motion) {
        touchUpdateFinger(finger.fingerID, finger.x, finger.y, true);
      }
      else if (finger_up) {
        touchUpdateFinger(finger.fingerID, finger.x, finger.y, false);
      }

#ifdef BLENDER_MOBILE
      touch_using_fingers_ = true;
      const TouchPointerPhase phase = finger_down  ? TOUCH_POINTER_DOWN :
                                      finger_up    ? TOUCH_POINTER_UP :
                                                     TOUCH_POINTER_MOVE;
      processAndroidTouchAt(event_ms, window, x_root, y_root, phase);
      if (finger_up && touchCountActiveFingers() == 0) {
        touch_using_fingers_ = false;
      }
#else
      active_touch_count_ = touchCountActiveFingers();
      if (finger_down && active_touch_count_ == 1) {
        touch_mode_ = TOUCH_MODE_PENDING_TAP;
        touch_start_x_ = x_root;
        touch_start_y_ = y_root;
        touch_last_x_ = x_root;
        touch_last_y_ = y_root;
        g_event = std::make_unique<GHOST_EventCursor>(
            event_ms, GHOST_kEventCursorMove, window, x_root, y_root, GHOST_TABLET_DATA_NONE);
      }
      else if (finger_motion && active_touch_count_ == 1) {
        g_event = std::make_unique<GHOST_EventCursor>(
            event_ms, GHOST_kEventCursorMove, window, x_root, y_root, GHOST_TABLET_DATA_NONE);
      }
      else if (finger_up && active_touch_count_ == 0) {
        if (touch_mode_ == TOUCH_MODE_PENDING_TAP) {
          pushEvent(std::make_unique<GHOST_EventCursor>(
              event_ms, GHOST_kEventCursorMove, window, x_root, y_root, GHOST_TABLET_DATA_NONE));
          pushEvent(std::make_unique<GHOST_EventButton>(event_ms,
                                                        GHOST_kEventButtonDown,
                                                        window,
                                                        GHOST_kButtonMaskLeft,
                                                        GHOST_TABLET_DATA_NONE));
          g_event = std::make_unique<GHOST_EventButton>(
              event_ms, GHOST_kEventButtonUp, window, GHOST_kButtonMaskLeft, GHOST_TABLET_DATA_NONE);
        }
        touchResetState();
      }
#endif
      break;
    }
    case SDL_EVENT_PINCH_BEGIN: {
      touch_pinch_active_ = true;
      touch_mode_ = TOUCH_MODE_MULTI;
#ifdef BLENDER_MOBILE
      /* Finger-spread already emits wheel zoom. Do not also inject trackpad+wheel
       * or leftover mouse buttons from the one-finger orbit. */
      GHOST_WindowSDL *window = findGhostWindowOrPrimary(
          SDL_GetWindowFromID_fallback(sdl_event->pinch.windowID));
      if (window != nullptr) {
        const uint64_t event_ms = SDL_NS_TO_MS(sdl_event->pinch.timestamp);
        if (touch_left_down_) {
          pushEvent(std::make_unique<GHOST_EventButton>(event_ms,
                                                        GHOST_kEventButtonUp,
                                                        window,
                                                        GHOST_kButtonMaskLeft,
                                                        GHOST_TABLET_DATA_NONE));
          touch_left_down_ = false;
        }
        if (touch_right_down_) {
          pushEvent(std::make_unique<GHOST_EventButton>(event_ms,
                                                        GHOST_kEventButtonUp,
                                                        window,
                                                        GHOST_kButtonMaskRight,
                                                        GHOST_TABLET_DATA_NONE));
          touch_right_down_ = false;
        }
        if (touch_middle_down_) {
          pushEvent(std::make_unique<GHOST_EventButton>(event_ms,
                                                        GHOST_kEventButtonUp,
                                                        window,
                                                        GHOST_kButtonMaskMiddle,
                                                        GHOST_TABLET_DATA_NONE));
          touch_middle_down_ = false;
        }
        if (touch_shift_down_) {
          pushEvent(std::make_unique<GHOST_EventKey>(
              event_ms, GHOST_kEventKeyUp, window, GHOST_kKeyLeftShift, false));
          touch_shift_down_ = false;
        }
      }
#endif
      break;
    }
    case SDL_EVENT_PINCH_UPDATE: {
      touch_pinch_active_ = true;
      break;
    }
    case SDL_EVENT_PINCH_END:
      touch_pinch_active_ = false;
      if (active_touch_count_ == 0) {
        touchResetState();
      }
      else if (active_touch_count_ == 1) {
        touch_mode_ = TOUCH_MODE_PENDING_TAP;
      }
      break;
  }

  if (g_event) {
    switch (g_event->getType()) {
      case GHOST_kEventWindowActivate: {
        window_manager_->setActiveWindow(g_event->getWindow());
        break;
      }
      case GHOST_kEventWindowDeactivate: {
        window_manager_->setWindowInactive(g_event->getWindow());
        break;
      }
      default: {
        break;
      }
    }
    pushEvent(std::move(g_event));
  }
}

GHOST_TSuccess GHOST_SystemSDL::getCursorPosition(int32_t &x, int32_t &y) const
{
  SDL_Window *win = SDL_GetMouseFocus();
  if (win == nullptr) {
    win = SDL_GL_GetCurrentWindow();
  }
  if (win == nullptr) {
    x = 0;
    y = 0;
    return GHOST_kFailure;
  }

  int x_win = 0, y_win = 0;
  SDL_GetWindowPosition(win, &x_win, &y_win);

  float xf = 0.0f, yf = 0.0f;
  SDL_GetMouseState(&xf, &yf);
  x = int32_t(xf) + x_win;
  y = int32_t(yf) + y_win;

  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemSDL::setCursorPosition(int32_t x, int32_t y)
{
#ifdef BLENDER_MOBILE
  /* Warping the OS cursor fights touch injection and freezes orbit. */
  (void)x;
  (void)y;
  return GHOST_kSuccess;
#else
  SDL_Window *win = SDL_GetMouseFocus();
  if (win == nullptr) {
    win = SDL_GL_GetCurrentWindow();
  }
  if (win == nullptr) {
    return GHOST_kFailure;
  }

  int x_win = 0, y_win = 0;
  SDL_GetWindowPosition(win, &x_win, &y_win);

  SDL_WarpMouseInWindow(win, x - x_win, y - y_win);
  return GHOST_kSuccess;
#endif
}

bool GHOST_SystemSDL::generateWindowExposeEvents()
{
  std::vector<GHOST_WindowSDL *>::iterator w_start = dirty_windows_.begin();
  std::vector<GHOST_WindowSDL *>::const_iterator w_end = dirty_windows_.end();
  bool anyProcessed = false;

  for (; w_start != w_end; ++w_start) {
    /* The caller doesn't have a time-stamp. */
    const uint64_t event_ms = getMilliSeconds();
    auto g_event = std::make_unique<GHOST_Event>(event_ms, GHOST_kEventWindowUpdate, *w_start);

    (*w_start)->validate();

    if (g_event) {
      // printf("Expose events pushed\n");
      pushEvent(std::move(g_event));
      anyProcessed = true;
    }
  }

  dirty_windows_.clear();
  return anyProcessed;
}

bool GHOST_SystemSDL::processEvents(bool waitForEvent)
{
  /* Get all the current events - translate them into
   * ghost events and call base class #pushEvent() method. */

  bool anyProcessed = false;

  do {
    GHOST_TimerManager *timerMgr = getTimerManager();

    if (waitForEvent && dirty_windows_.empty() && !SDL_HasEvents(SDL_EVENT_FIRST, SDL_EVENT_LAST))
    {
      uint64_t next = timerMgr->nextFireTime();

      if (next == GHOST_kFireTimeNever) {
        SDL_WaitEventTimeout(nullptr, -1);
        // SleepTillEvent(display_, -1);
      }
      else {
        int64_t maxSleep = next - getMilliSeconds();

        if (maxSleep >= 0) {
          SDL_WaitEventTimeout(nullptr, next - getMilliSeconds());
          // SleepTillEvent(display_, next - getMilliSeconds()); /* X11. */
        }
      }
    }

    if (timerMgr->fireTimers(getMilliSeconds())) {
      anyProcessed = true;
    }

    SDL_Event sdl_event;
    while (SDL_PollEvent(&sdl_event)) {
      processEvent(&sdl_event);
      anyProcessed = true;
    }

    if (generateWindowExposeEvents()) {
      anyProcessed = true;
    }
  } while (waitForEvent && !anyProcessed);

  return anyProcessed;
}

GHOST_WindowSDL *GHOST_SystemSDL::findGhostWindow(SDL_Window *sdl_win)
{
  if (sdl_win == nullptr) {
    return nullptr;
  }
  /* It is not entirely safe to do this as the back-pointer may point
   * to a window that has recently been removed.
   * We should always check the window manager's list of windows
   * and only process events on these windows. */

  const std::vector<GHOST_IWindow *> &win_vec = window_manager_->getWindows();

  std::vector<GHOST_IWindow *>::const_iterator win_it = win_vec.begin();
  std::vector<GHOST_IWindow *>::const_iterator win_end = win_vec.end();

  for (; win_it != win_end; ++win_it) {
    GHOST_WindowSDL *window = static_cast<GHOST_WindowSDL *>(*win_it);
    if (window->getSDLWindow() == sdl_win) {
      return window;
    }
  }
  return nullptr;
}

void GHOST_SystemSDL::addDirtyWindow(GHOST_WindowSDL *bad_wind)
{
  GHOST_ASSERT((bad_wind != nullptr), "addDirtyWindow() nullptr ptr trapped (window)");

  dirty_windows_.push_back(bad_wind);
}

GHOST_TSuccess GHOST_SystemSDL::getButtons(GHOST_Buttons &buttons) const
{
  SDL_MouseButtonFlags state = SDL_GetMouseState(nullptr, nullptr);
  buttons.set(GHOST_kButtonMaskLeft, (state & SDL_BUTTON_LMASK) != 0);
  buttons.set(GHOST_kButtonMaskMiddle, (state & SDL_BUTTON_MMASK) != 0);
  buttons.set(GHOST_kButtonMaskRight, (state & SDL_BUTTON_RMASK) != 0);

  return GHOST_kSuccess;
}

GHOST_TCapabilityFlag GHOST_SystemSDL::getCapabilities() const
{
  return GHOST_TCapabilityFlag(
      GHOST_CAPABILITY_FLAG_ALL &
      /* NOTE: order the following flags as they they're declared in the source. */
      ~(
          /* This SDL back-end has not yet implemented image copy/paste. */
          GHOST_kCapabilityClipboardImage |
          /* This SDL back-end has not yet implemented color sampling the desktop. */
          GHOST_kCapabilityDesktopSample |
          /* No support yet for IME input methods. */
          GHOST_kCapabilityInputIME |
          /* No support for window decoration styles. */
          GHOST_kCapabilityWindowDecorationStyles |
          /* No support for precisely placing windows on multiple monitors. */
          GHOST_kCapabilityMultiMonitorPlacement |
          /* No support for a Hyper modifier key. */
          GHOST_kCapabilityKeyboardHyperKey |
          /* No support yet for RGBA mouse cursors. */
          GHOST_kCapabilityCursorRGBA |
          /* No support yet for dynamic cursor generation. */
          GHOST_kCapabilityCursorGenerator |
          /* No support for window path meta-data. */
          GHOST_kCapabilityWindowPath
#ifdef BLENDER_MOBILE
          /* Cursor warp fights touch/mouse injection and freezes orbit. */
          | GHOST_kCapabilityCursorWarp
          /* Front-buffer depth reads stall or fail on mobile Vulkan. */
          | GHOST_kCapabilityGPUReadFrontBuffer
#endif
          ));
}

char *GHOST_SystemSDL::getClipboard(bool selection) const
{
  /* The clipboard must be freed with `SDL_free`, copy for the return value. */
  char *sdl_text = selection ? SDL_GetPrimarySelectionText() : SDL_GetClipboardText();
  if (sdl_text == nullptr) {
    return nullptr;
  }
  char *result = strdup(sdl_text);
  SDL_free(sdl_text);
  return result;
}

void GHOST_SystemSDL::putClipboard(const char *buffer, bool selection) const
{
  if (selection) {
    SDL_SetPrimarySelectionText(buffer);
  }
  else {
    SDL_SetClipboardText(buffer);
  }
}

uint64_t GHOST_SystemSDL::getMilliSeconds() const
{
  return SDL_GetTicks();
}
