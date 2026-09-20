/* SPDX-FileCopyrightText: 2011-2023 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 * Declaration of GHOST_SystemSDL class.
 */

#pragma once

#include "../GHOST_Types.hh"
#include "GHOST_Event.hh"
#include "GHOST_System.hh"
#include "GHOST_TimerManager.hh"
#include "GHOST_WindowSDL.hh"

#include <SDL3/SDL.h>

class GHOST_WindowSDL;

class GHOST_SystemSDL : public GHOST_System {
 public:
  void addDirtyWindow(GHOST_WindowSDL *bad_wind);

  GHOST_SystemSDL();
  ~GHOST_SystemSDL();

  bool processEvents(bool waitForEvent) override;

  bool setConsoleWindowState(GHOST_TConsoleWindowState /*action*/) override
  {
    return false;
  }

  GHOST_TSuccess getModifierKeys(GHOST_ModifierKeys &keys) const override;

  GHOST_TSuccess getButtons(GHOST_Buttons &buttons) const override;

  GHOST_TCapabilityFlag getCapabilities() const override;

  char *getClipboard(bool selection) const override;

  void putClipboard(const char *buffer, bool selection) const override;

  uint64_t getMilliSeconds() const override;

  uint8_t getNumDisplays() const override;

  GHOST_TSuccess getCursorPosition(int32_t &x, int32_t &y) const override;

  GHOST_TSuccess setCursorPosition(int32_t x, int32_t y) override;

  void getAllDisplayDimensions(uint32_t &width, uint32_t &height) const override;

  void getMainDisplayDimensions(uint32_t &width, uint32_t &height) const override;

  GHOST_IContext *createOffscreenContext(GHOST_GPUSettings gpu_settings) override;

  GHOST_TSuccess disposeContext(GHOST_IContext *context) override;

 private:
  GHOST_TSuccess init() override;

  GHOST_IWindow *createWindow(const char *title,
                              int32_t left,
                              int32_t top,
                              uint32_t width,
                              uint32_t height,
                              GHOST_TWindowState state,
                              GHOST_GPUSettings gpu_settings,
                              const bool exclusive = false,
                              const bool is_dialog = false,
                              const GHOST_IWindow *parent_window = nullptr) override;

  /* SDL specific */
  GHOST_WindowSDL *findGhostWindow(SDL_Window *sdl_win);

  bool generateWindowExposeEvents();

  void processEvent(SDL_Event *sdl_event);

  /** The vector of windows that need to be updated. */
  std::vector<GHOST_WindowSDL *> dirty_windows_;

  GHOST_WindowSDL *findGhostWindowOrPrimary(SDL_Window *sdl_win);

  /* Touch-as-mouse (Android). */
  enum TouchInteractionMode {
    TOUCH_MODE_NONE = 0,
    TOUCH_MODE_PENDING_TAP,
    TOUCH_MODE_ORBIT,
    TOUCH_MODE_MULTI,
  };

  struct TouchFingerState {
    SDL_FingerID finger_id = 0;
    float x = 0.0f;
    float y = 0.0f;
    bool active = false;
  };

  static constexpr int kMaxTouchFingers = 10;
  static constexpr float kTouchDragThresholdPx = 16.0f;

  enum TouchPointerPhase {
    TOUCH_POINTER_DOWN = 0,
    TOUCH_POINTER_MOVE,
    TOUCH_POINTER_UP,
  };

  TouchFingerState touch_fingers_[kMaxTouchFingers];
  int active_touch_count_ = 0;
  TouchInteractionMode touch_mode_ = TOUCH_MODE_NONE;
  int32_t touch_start_x_ = 0;
  int32_t touch_start_y_ = 0;
  int32_t touch_last_x_ = 0;
  int32_t touch_last_y_ = 0;
  bool touch_pinch_active_ = false;
  bool touch_using_fingers_ = false;
  bool touch_middle_down_ = false;
  bool touch_left_down_ = false;
  bool touch_right_down_ = false;
  bool touch_shift_down_ = false;
  float touch_pinch_dist_ = -1.0f;

  void touchResetState();
  void touchUpdateFinger(SDL_FingerID finger_id, float x, float y, bool active);
  int touchCountActiveFingers() const;
  void touchGetCentroid(float &x_out, float &y_out) const;
  float touchFingerSpread() const;

  bool processAndroidTouchAt(uint64_t event_ms,
                             GHOST_WindowSDL *window,
                             int32_t x_root,
                             int32_t y_root,
                             TouchPointerPhase phase);
};
