# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later

"""Force a phone-sized main screen and expose mobile settings."""

from __future__ import annotations

import os
import sys

import bpy
from bpy.app.handlers import persistent
from bpy.props import BoolProperty, EnumProperty, FloatProperty, IntProperty, StringProperty
from bpy.types import Menu, Operator, Panel

_apply_step = 0
_last_landscape = None
_KEEP_AREA_TYPES = {'VIEW_3D', 'TOPBAR', 'STATUSBAR'}
_pending_open = ""
_opening = False


def is_android() -> bool:
    if os.environ.get("BLENDER_ANDROID", "") == "1":
        return True
    if os.path.exists("/system/build.prop"):
        return True
    return sys.platform == "linux" and bool(os.environ.get("ANDROID_ROOT"))


def is_ios() -> bool:
    if os.environ.get("BLENDER_IOS", "") == "1":
        return True
    return sys.platform == "darwin" and os.environ.get("BLENDER_MOBILE", "") == "1"


def is_mobile() -> bool:
    if os.environ.get("BLENDER_MOBILE", "") == "1":
        return True
    return is_android() or is_ios()


def recommended_ui_scale() -> float:
    win = bpy.context.window
    if win is None:
        return 1.55
    short = min(int(win.width), int(win.height))
    if short >= 1080:
        return 1.70
    if short >= 720:
        return 1.55
    return 1.40


def ui_scale_percent() -> int:
    try:
        return int(round(float(bpy.context.preferences.view.ui_scale) * 100))
    except Exception:
        return 100


def set_ui_scale(value: float, *, save: bool = True) -> float:
    prefs = bpy.context.preferences
    scale = max(0.70, min(3.00, float(value)))
    scale = round(scale * 20.0) / 20.0
    prefs.view.ui_scale = scale
    try:
        for window in bpy.context.window_manager.windows:
            for area in window.screen.areas:
                area.tag_redraw()
    except Exception:
        pass
    if save:
        try:
            bpy.ops.wm.save_userpref()
        except Exception:
            pass
    return scale


def _configure_view3d(space, *, toolbar: bool | None = None, sidebar: bool | None = None) -> None:
    if toolbar is None:
        toolbar = False
    if sidebar is None:
        sidebar = False
    space.show_region_ui = sidebar
    space.show_region_toolbar = toolbar
    space.show_region_header = True
    if hasattr(space, "show_region_tool_header"):
        space.show_region_tool_header = False
    space.show_region_footer = False
    if hasattr(space, "show_region_asset_shelf"):
        space.show_region_asset_shelf = False
    if hasattr(space, "show_region_hud"):
        space.show_region_hud = False
    space.show_gizmo = True
    space.show_gizmo_navigate = True
    space.show_gizmo_tool = True
    if hasattr(space, "show_gizmo_context"):
        space.show_gizmo_context = True
    if hasattr(space, "show_gizmo_object_translate"):
        space.show_gizmo_object_translate = True
    if hasattr(space, "show_gizmo_object_rotate"):
        space.show_gizmo_object_rotate = True
    if hasattr(space, "show_gizmo_object_scale"):
        space.show_gizmo_object_scale = True
    space.overlay.show_overlays = True
    if hasattr(space, "show_region_header"):
        space.show_region_header = True
    overlay = space.overlay
    if hasattr(overlay, "show_stats"):
        overlay.show_stats = False
    if hasattr(overlay, "show_text"):
        overlay.show_text = False
    if hasattr(overlay, "show_look_dev"):
        overlay.show_look_dev = False


def apply_seamless_chrome() -> None:
    prefs = bpy.context.preferences
    view = prefs.view
    if hasattr(view, "border_width"):
        view.border_width = 5
    if hasattr(view, "show_area_handle"):
        view.show_area_handle = True
    if hasattr(view, "header_align"):
        try:
            view.header_align = 'TOP'
        except Exception:
            pass
    if hasattr(view, "ui_line_width"):
        try:
            view.ui_line_width = 'THICK'
        except Exception:
            pass
    apps = getattr(prefs, "apps", None)
    if apps is not None:
        if hasattr(apps, "show_edge_resize"):
            apps.show_edge_resize = True
        if hasattr(apps, "show_corner_split"):
            apps.show_corner_split = True
    if hasattr(prefs.system, "use_region_overlap"):
        prefs.system.use_region_overlap = True
    if hasattr(prefs.system, "show_panel_tabs_compact"):
        prefs.system.show_panel_tabs_compact = True

    try:
        theme = prefs.themes[0]
        ui = theme.user_interface
        bg = (0.18, 0.18, 0.18)
        try:
            g = theme.view_3d.space.gradients.high_gradient
            bg = (float(g[0]), float(g[1]), float(g[2]))
        except Exception:
            pass
        if hasattr(ui, "panel_roundness"):
            ui.panel_roundness = 0.12
        if hasattr(ui, "menu_shadow_width"):
            ui.menu_shadow_width = 0
        if hasattr(ui, "menu_shadow_fac"):
            ui.menu_shadow_fac = 0.0
        if hasattr(ui, "widget_emboss"):
            ui.widget_emboss = (0.0, 0.0, 0.0, 0.0)
        if hasattr(ui, "editor_border"):
            ui.editor_border = (0.08, 0.08, 0.08)
        if hasattr(ui, "editor_outline"):
            ui.editor_outline = (0.32, 0.32, 0.32, 1.0)
        if hasattr(ui, "editor_outline_active"):
            ui.editor_outline_active = (0.55, 0.55, 0.55, 1.0)
        for name in (
            "wcol_regular",
            "wcol_tool",
            "wcol_toolbar_item",
            "wcol_box",
            "wcol_menu",
            "wcol_pulldown",
            "wcol_menu_back",
            "wcol_tooltip",
        ):
            wcol = getattr(ui, name, None)
            if wcol is not None and hasattr(wcol, "outline"):
                try:
                    wcol.outline = (bg[0], bg[1], bg[2], 0.0)
                except Exception:
                    pass
        header = (bg[0], bg[1], bg[2], 0.42)
        solid = (bg[0], bg[1], bg[2], 1.0)
        try:
            theme.view_3d.space.header = header
        except Exception:
            pass
        try:
            theme.topbar.space.header = solid
            if hasattr(theme.topbar.space, "back"):
                theme.topbar.space.back = solid
        except Exception:
            pass
        try:
            theme.statusbar.space.header = solid
            if hasattr(theme.statusbar.space, "back"):
                theme.statusbar.space.back = solid
        except Exception:
            pass
    except Exception:
        pass


def _content_areas(screen):
    return [area for area in screen.areas if area.type not in {'TOPBAR', 'STATUSBAR'}]


def _exit_area_fullscreen(window, screen) -> None:
    if not getattr(screen, "show_fullscreen", False):
        return
    area = next(iter(screen.areas), None)
    if area is None:
        return
    try:
        with bpy.context.temp_override(window=window, screen=screen, area=area):
            bpy.ops.screen.screen_full_area(use_hide_panels=False)
    except Exception:
        try:
            with bpy.context.temp_override(window=window, screen=screen, area=area):
                bpy.ops.screen.back_to_previous()
        except Exception:
            pass


def _split_content(window, screen, area, direction: str, factor: float, new_type: str | None):
    before = {item.as_pointer() for item in screen.areas}
    try:
        with bpy.context.temp_override(window=window, screen=screen, area=area):
            bpy.ops.screen.area_split(direction=direction, factor=factor)
    except Exception as exc:
        print("android_phone: split failed", exc)
        return None
    for candidate in screen.areas:
        if candidate.as_pointer() not in before:
            if new_type:
                try:
                    candidate.type = new_type
                except Exception:
                    pass
            return candidate
    return None


def apply_adjustable_layout(*, reset: bool = False) -> None:
    wm = bpy.context.window_manager
    if wm is None:
        return
    for window in wm.windows:
        screen = window.screen
        if hasattr(screen, "show_statusbar"):
            screen.show_statusbar = False
        _exit_area_fullscreen(window, screen)
        if reset:
            close_extra_editors()
            _ensure_view3d(screen)
        areas = _content_areas(screen)
        if len(areas) <= 1:
            source = areas[0] if areas else None
            if source is None:
                _ensure_view3d(screen)
                areas = _content_areas(screen)
                source = areas[0] if areas else None
            if source is not None:
                if source.type != 'VIEW_3D':
                    try:
                        source.type = 'VIEW_3D'
                    except Exception:
                        pass
                _split_content(window, screen, source, 'VERTICAL', 0.70, 'PROPERTIES')


def apply_phone_prefs(*, force_scale: bool = False) -> None:
    try:
        from . import android_touch_nav

        android_touch_nav.ensure_view3d_touch_keymap()
    except Exception:
        pass

    prefs = bpy.context.preferences
    view = prefs.view
    if force_scale:
        set_ui_scale(recommended_ui_scale(), save=False)
    if hasattr(view, "minimum_ui_scale"):
        view.minimum_ui_scale = 0.5
    view.show_splash = True
    view.show_tooltips = False
    view.show_developer_ui = False
    if hasattr(view, "show_statusbar"):
        view.show_statusbar = False
    if hasattr(view, "show_navigate_ui"):
        view.show_navigate_ui = True
    if hasattr(view, "show_gizmo"):
        view.show_gizmo = True
    if hasattr(view, "mini_axis_type"):
        view.mini_axis_type = 'GIZMO'
    if hasattr(view, "gizmo_size_navigate_v3d"):
        if view.gizmo_size_navigate_v3d < 90 or view.gizmo_size_navigate_v3d > 160:
            view.gizmo_size_navigate_v3d = 110
    if hasattr(view, "gizmo_size") and view.gizmo_size < 90:
        view.gizmo_size = 110

    inputs = prefs.inputs
    if hasattr(inputs, "use_mouse_continuous"):
        inputs.use_mouse_continuous = False
    if hasattr(inputs, "use_mouse_emulate_3_button"):
        inputs.use_mouse_emulate_3_button = False
    if hasattr(inputs, "use_mouse_depth_navigate"):
        inputs.use_mouse_depth_navigate = False
    if hasattr(inputs, "use_zoom_to_mouse"):
        inputs.use_zoom_to_mouse = True

    try:
        style = prefs.ui_styles[0]
        if style.widget.points < 12:
            style.widget.points = 13
        if style.panel_title.points < 12:
            style.panel_title.points = 13
    except Exception:
        pass
    apply_seamless_chrome()
    apply_phone_file_paths()
    if hasattr(view, "filebrowser_display_type"):
        view.filebrowser_display_type = 'SCREEN'
    if hasattr(view, "preferences_display_type"):
        view.preferences_display_type = 'SCREEN'
    if hasattr(view, "render_display_type"):
        view.render_display_type = 'SCREEN'
    apply_cycles_cpu(set_engine=True)
    try:
        prefs.filepaths.use_load_ui = False
    except Exception:
        pass
    try:
        prefs.filepaths.use_scripts_auto_execute = False
    except Exception:
        pass
    if hasattr(view, "use_save_prompt"):
        view.use_save_prompt = False
    elif hasattr(prefs, "use_save_prompt"):
        prefs.use_save_prompt = False


def _enable_cycles_later():
    apply_cycles_cpu(set_engine=True)
    return None


def apply_cycles_cpu(*, set_engine: bool = True) -> bool:
    import sys

    try:
        import addon_utils

        for path in addon_utils.paths():
            if path and path not in sys.path:
                sys.path.append(path)

        def _cycles_enable_error(ex):
            print("Cycles enable failed:", ex)

        addon_utils.enable(
            "cycles",
            default_set=True,
            persistent=True,
            handle_error=_cycles_enable_error,
        )
    except Exception as ex:
        print("Cycles enable failed:", ex)
    scene = getattr(bpy.context, "scene", None)
    if scene is None:
        return False
    try:
        items = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
        if "CYCLES" not in {item.identifier for item in items}:
            return False
    except Exception:
        return False
    if set_engine:
        scene.render.engine = "CYCLES"
    cycles = getattr(scene, "cycles", None)
    if cycles is not None and hasattr(cycles, "device"):
        try:
            cycles.device = "CPU"
        except Exception:
            pass
    return True


def _files_dir() -> str:
    home = os.environ.get("HOME", "")
    if home:
        return os.path.dirname(home)
    return os.environ.get("XDG_CONFIG_HOME", "")


def phone_storage_root() -> str:
    return os.environ.get("BLENDER_ANDROID_STORAGE", "/storage/emulated/0")


def phone_downloads_dir() -> str:
    return os.environ.get(
        "BLENDER_ANDROID_DOWNLOADS",
        os.path.join(phone_storage_root(), "Download"),
    )


def phone_open_start_dir() -> str:
    candidates = (
        phone_downloads_dir(),
        phone_blends_dir(),
        os.environ.get(
            "BLENDER_ANDROID_DOCUMENTS",
            os.path.join(phone_storage_root(), "Documents"),
        ),
        phone_storage_root(),
    )
    for path in candidates:
        if path and os.path.isdir(path):
            return path
    return phone_storage_root()


def invoke_phone_file_browser(start_dir: str | None = None) -> None:
    prefs = bpy.context.preferences
    if hasattr(prefs.view, "filebrowser_display_type"):
        prefs.view.filebrowser_display_type = "SCREEN"
    folder = start_dir or phone_open_start_dir()
    try:
        os.makedirs(folder, exist_ok=True)
    except Exception:
        folder = phone_storage_root()
    filepath = os.path.join(folder, "untitled.blend")
    bpy.ops.wm.open_mainfile(
        "INVOKE_DEFAULT",
        filepath=filepath,
        load_ui=False,
        use_scripts=False,
    )


def open_blend_file(filepath: str) -> None:
    bpy.ops.wm.open_mainfile(
        "EXEC_DEFAULT",
        filepath=filepath,
        load_ui=False,
        use_scripts=False,
        display_file_selector=False,
    )


def queue_open_blend(filepath: str) -> None:
    global _pending_open
    if not filepath:
        return
    _pending_open = filepath
    try:
        bpy.app.timers.register(_deferred_open, first_interval=0.08)
    except Exception:
        _deferred_open()


def _deferred_open():
    global _pending_open, _opening
    path = _pending_open
    _pending_open = ""
    if _opening or not path or not os.path.isfile(path):
        return None
    _opening = True
    try:
        open_blend_file(path)
    except Exception as exc:
        print("android_phone: open failed", path, exc)
        _opening = False
    return None


def restore_after_open() -> None:
    wm = bpy.context.window_manager
    if wm is None:
        return
    for window in wm.windows:
        screen = window.screen
        if hasattr(screen, "show_statusbar"):
            screen.show_statusbar = False
        _exit_area_fullscreen(window, screen)
        for area in list(screen.areas):
            if area.type == "FILE_BROWSER":
                try:
                    area.type = "VIEW_3D"
                except Exception:
                    pass
        if not any(area.type == "VIEW_3D" for area in screen.areas):
            _ensure_view3d(screen)
        areas = _content_areas(screen)
        if len(areas) == 1 and areas[0].type == "VIEW_3D":
            _split_content(window, screen, areas[0], "VERTICAL", 0.70, "PROPERTIES")
    apply_view3d_settings()


def frame_loaded_scene() -> None:
    wm = bpy.context.window_manager
    if wm is None:
        return
    for window in wm.windows:
        for area in window.screen.areas:
            if area.type != "VIEW_3D":
                continue
            region = next((item for item in area.regions if item.type == "WINDOW"), None)
            space = area.spaces.active
            if hasattr(space, "clip_end"):
                space.clip_end = max(float(space.clip_end), 10000.0)
            if region is None:
                continue
            try:
                with bpy.context.temp_override(
                    window=window, screen=window.screen, area=area, region=region
                ):
                    bpy.ops.view3d.view_all(center=True)
            except Exception as exc:
                print("android_phone: view_all failed", exc)


def phone_blends_dir() -> str:
    return os.environ.get(
        "BLENDER_ANDROID_BLENDS",
        os.path.join(phone_storage_root(), "Download", "Blender"),
    )


def apply_phone_file_paths() -> None:
    root = phone_storage_root()
    blends = phone_blends_dir()
    downloads = os.environ.get("BLENDER_ANDROID_DOWNLOADS", os.path.join(root, "Download"))
    documents = os.environ.get("BLENDER_ANDROID_DOCUMENTS", os.path.join(root, "Documents"))
    pictures = os.environ.get("BLENDER_ANDROID_PICTURES", os.path.join(root, "Pictures"))
    music = os.environ.get("BLENDER_ANDROID_MUSIC", os.path.join(root, "Music"))
    movies = os.environ.get("BLENDER_ANDROID_MOVIES", os.path.join(root, "Movies"))
    for path in (blends, downloads, documents):
        try:
            os.makedirs(path, exist_ok=True)
        except Exception:
            pass

    fps = bpy.context.preferences.filepaths
    if hasattr(fps, "render_output_directory") and not fps.render_output_directory:
        fps.render_output_directory = blends
    if hasattr(fps, "texture_directory") and not fps.texture_directory:
        fps.texture_directory = pictures
    if hasattr(fps, "sound_directory"):
        if not fps.sound_directory or fps.sound_directory in {"/", "//"}:
            fps.sound_directory = music
    if hasattr(fps, "font_directory") and not fps.font_directory:
        fps.font_directory = "/system/fonts"
    if hasattr(fps, "render_cache_directory") and not getattr(fps, "render_cache_directory", ""):
        try:
            fps.render_cache_directory = blends
        except Exception:
            pass

    ensure_phone_bookmarks(root, blends, downloads, documents, pictures, movies, music)


def ensure_phone_bookmarks(root, blends, downloads, documents, pictures, movies, music) -> None:
    config = os.environ.get("BLENDER_USER_CONFIG", "")
    if not config:
        return
    try:
        os.makedirs(config, exist_ok=True)
    except Exception:
        return
    path = os.path.join(config, "bookmarks.txt")
    wanted = [
        ("Phone Storage", root),
        ("Download", downloads),
        ("Blender Files", blends),
        ("Documents", documents),
        ("Pictures", pictures),
        ("Movies", movies),
        ("Music", music),
    ]
    existing = ""
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                existing = handle.read()
        except Exception:
            existing = ""
    missing = [(name, folder) for name, folder in wanted if folder and folder not in existing]
    if not missing and existing:
        return
    lines = existing.splitlines() if existing else ["[Bookmarks]", "[Recent]"]
    if "[Bookmarks]" not in lines:
        lines.insert(0, "[Bookmarks]")
    insert_at = 1
    if "[Bookmarks]" in lines:
        insert_at = lines.index("[Bookmarks]") + 1
    extra = []
    for name, folder in missing:
        extra.extend([f"!{name}", folder])
    lines[insert_at:insert_at] = extra
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines).rstrip() + "\n")
    except Exception:
        return
    # Bookmarks are read the next time the file browser opens.


def _write_android_cmd(action: str, extra: str = "") -> None:
    root = _files_dir()
    if not root:
        return
    path = os.path.join(root, "android_cmd.txt")
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(action + "\n")
            if extra:
                handle.write(extra + "\n")
    except Exception:
        pass


_last_opened_path = ""


def _poll_file_bridge():
    global _last_opened_path
    if not is_mobile():
        return None
    root = _files_dir()
    if not root:
        return 0.5
    for name in ("pending_open.txt", "android_result.txt"):
        path = os.path.join(root, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as handle:
                text = handle.read().strip()
        except Exception:
            continue
        try:
            os.remove(path)
        except Exception:
            pass
        if not text or text in {"CANCEL", "ERROR"} or text.startswith("ERROR"):
            continue
        filepath = text.splitlines()[0].strip()
        if not filepath or filepath == _last_opened_path or not os.path.isfile(filepath):
            continue
        if filepath.lower().endswith((".blend", ".blend1", ".blend2")):
            _last_opened_path = filepath
            try:
                queue_open_blend(filepath)
            except Exception as exc:
                print("android_phone: open failed", filepath, exc)
        else:
            try:
                bpy.ops.image.open(filepath=filepath)
            except Exception:
                print("android_phone: received file", filepath)
    env_path = os.environ.get("BLENDER_OPEN_PATH", "")
    if env_path and env_path != _last_opened_path and os.path.isfile(env_path):
        _last_opened_path = env_path
        if env_path.lower().endswith((".blend", ".blend1", ".blend2")):
            try:
                queue_open_blend(env_path)
            except Exception as exc:
                print("android_phone: env open failed", env_path, exc)
    return 0.5


def _is_extra_editor(area) -> bool:
    if area.type in _KEEP_AREA_TYPES:
        return False
    return True


def close_extra_editors() -> None:
    wm = bpy.context.window_manager
    if wm is None:
        return
    for window in wm.windows:
        screen = window.screen
        if hasattr(screen, "show_statusbar"):
            screen.show_statusbar = False
        for _ in range(16):
            extra = next((area for area in screen.areas if _is_extra_editor(area)), None)
            if extra is None:
                break
            try:
                with bpy.context.temp_override(window=window, screen=screen, area=extra):
                    bpy.ops.screen.area_close()
            except Exception:
                try:
                    extra.type = 'VIEW_3D'
                except Exception:
                    break


def _ensure_view3d(screen) -> None:
    if any(area.type == 'VIEW_3D' for area in screen.areas):
        return
    for area in screen.areas:
        if area.type not in {'TOPBAR', 'STATUSBAR'}:
            area.type = 'VIEW_3D'
            return


def apply_view3d_settings(*, toolbar: bool | None = None, sidebar: bool | None = None) -> None:
    wm = bpy.context.window_manager
    if wm is None:
        return
    try:
        from . import android_touch_nav

        android_touch_nav.ensure_view3d_touch_keymap()
    except Exception:
        pass
    for window in wm.windows:
        screen = window.screen
        if hasattr(screen, "show_statusbar"):
            screen.show_statusbar = False
        _ensure_view3d(screen)
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                _configure_view3d(area.spaces.active, toolbar=toolbar, sidebar=sidebar)
                try:
                    with bpy.context.temp_override(window=window, screen=screen, area=area):
                        bpy.ops.wm.tool_set_by_id(name="builtin.none")
                except Exception:
                    pass


def force_mobile_screen(*, toolbar: bool = False, sidebar: bool = False, reset: bool = False) -> None:
    apply_phone_prefs()
    apply_adjustable_layout(reset=reset)
    apply_view3d_settings(toolbar=toolbar, sidebar=sidebar)


def _apply_sequence():
    global _apply_step
    if not is_mobile():
        return None
    if _apply_step == 0:
        restore_after_open()
        _apply_step = 1
        return 0.3
    if _apply_step == 1:
        if bpy.data.filepath:
            frame_loaded_scene()
        _apply_step = 2
    return None


def _poll_orientation():
    global _last_landscape
    if not is_mobile():
        return None
    win = bpy.context.window
    if win is None:
        return 0.75
    landscape = int(win.width) > int(win.height)
    if _last_landscape is None:
        _last_landscape = landscape
        return 0.75
    if landscape != _last_landscape:
        _last_landscape = landscape
        try:
            apply_view3d_settings()
            for window in bpy.context.window_manager.windows:
                for area in window.screen.areas:
                    area.tag_redraw()
        except Exception:
            pass
    return 0.75


@persistent
def _on_file_load(_dummy) -> None:
    global _apply_step, _opening
    if not is_mobile():
        return
    _opening = False
    apply_view3d_settings()
    _apply_step = 0
    try:
        bpy.app.timers.register(_apply_sequence, first_interval=0.2)
    except Exception:
        _apply_sequence()


class WM_OT_android_open_blend_path(Operator):
    bl_idname = "wm.android_open_blend_path"
    bl_label = "Open Project"
    bl_description = "Open this .blend from the phone"

    filepath: StringProperty(subtype='FILE_PATH')

    def execute(self, context):
        if not self.filepath or not os.path.isfile(self.filepath):
            self.report({'ERROR'}, "File is gone")
            return {'CANCELLED'}
        queue_open_blend(self.filepath)
        self.report({'INFO'}, os.path.basename(self.filepath))
        return {'FINISHED'}


class WM_OT_android_open_file(Operator):
    bl_idname = "wm.android_open_file"
    bl_label = "Open Project"
    bl_description = "Browse Download for a .blend and open it"

    def execute(self, context):
        apply_phone_file_paths()
        try:
            invoke_phone_file_browser(phone_open_start_dir())
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}
        return {'FINISHED'}


class WM_OT_android_save_file(Operator):
    bl_idname = "wm.android_save_file"
    bl_label = "Save to Phone"
    bl_description = "Save this file into Download, Files, or Drive"

    def execute(self, context):
        folder = phone_blends_dir()
        try:
            os.makedirs(folder, exist_ok=True)
        except Exception:
            folder = _files_dir()
        name = bpy.path.basename(bpy.data.filepath) or "untitled.blend"
        dest = os.path.join(folder, name)
        try:
            bpy.ops.wm.save_as_mainfile(filepath=dest)
        except Exception as exc:
            self.report({'ERROR'}, f"Could not save: {exc}")
            return {'CANCELLED'}
        self.report({'INFO'}, f"Saved to {dest}")
        return {'FINISHED'}


class WM_OT_android_browse_storage(Operator):
    bl_idname = "wm.android_browse_storage"
    bl_label = "Browse Phone Files"
    bl_description = "Open Blender's file browser in Download/Blender"

    def execute(self, context):
        apply_phone_file_paths()
        try:
            invoke_phone_file_browser(phone_blends_dir())
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}
        return {'FINISHED'}


class WM_OT_android_grant_files(Operator):
    bl_idname = "wm.android_grant_files"
    bl_label = "Allow File Access"
    bl_description = "Ask Android for permission to read and write phone storage"

    def execute(self, context):
        if is_ios():
            try:
                import ctypes

                ctypes.CDLL(None).blender_ios_present_document_picker()
            except Exception as exc:
                self.report({'ERROR'}, str(exc))
                return {'CANCELLED'}
            self.report({'INFO'}, "Pick a .blend from Files")
            return {'FINISHED'}
        _write_android_cmd("grant")
        self.report({'INFO'}, "Allow all-files access for Blender")
        return {'FINISHED'}


class WM_OT_android_ui_scale(Operator):
    bl_idname = "wm.android_ui_scale"
    bl_label = "UI Scale"
    bl_description = "Make buttons and text larger or smaller"

    delta: FloatProperty(
        name="Delta",
        description="Amount to change the UI scale",
        default=0.10,
        min=-1.0,
        max=1.0,
    )
    value: FloatProperty(
        name="Scale",
        description="Absolute UI scale, or 0 to use delta",
        default=0.0,
        min=0.0,
        max=3.0,
    )

    def execute(self, context):
        current = float(context.preferences.view.ui_scale)
        target = self.value if self.value > 0.0 else current + self.delta
        scale = set_ui_scale(target)
        self.report({'INFO'}, f"UI scale {int(round(scale * 100))}%")
        return {'FINISHED'}


class WM_OT_android_apply_layout(Operator):
    bl_idname = "wm.android_apply_layout"
    bl_label = "Reset Editors"
    bl_description = "3D view plus a properties editor you can drag to resize"

    def execute(self, context):
        force_mobile_screen(reset=True)
        self.report({'INFO'}, "Editors reset — drag the gray bars to resize")
        return {'FINISHED'}


class WM_OT_android_start(Operator):
    bl_idname = "wm.android_start"
    bl_label = "Start"
    bl_description = "Apply phone layout, save preferences, and start"

    def execute(self, context):
        apply_phone_prefs(force_scale=True)
        force_mobile_screen(reset=True)
        try:
            bpy.ops.wm.save_userpref()
        except Exception:
            pass
        return {'FINISHED'}


class WM_OT_android_mobile_settings(Operator):
    bl_idname = "wm.android_mobile_settings"
    bl_label = "Phone Settings"
    bl_description = "Size, gizmos, and sidebars for a phone"

    ui_scale: FloatProperty(
        name="UI Scale",
        description="Make buttons and text larger or smaller",
        min=0.70,
        max=3.00,
        step=5,
        precision=2,
        default=1.55,
        update=None,
    )
    gizmo_nav: IntProperty(
        name="Nav Gizmo",
        description="Size of the orbit widget in the corner",
        min=40,
        max=280,
        default=110,
    )
    gizmo_size: IntProperty(
        name="Gizmo Size",
        description="Size of transform gizmos",
        min=40,
        max=200,
        default=110,
    )
    show_toolbar: BoolProperty(
        name="Toolbar (T)",
        description="Show the left tool strip",
        default=False,
    )
    show_sidebar: BoolProperty(
        name="Sidebar (N)",
        description="Show the right properties strip",
        default=False,
    )
    show_overlays: BoolProperty(
        name="Overlays",
        description="Show grid, floor, and outlines",
        default=True,
    )

    def invoke(self, context, _event):
        prefs = context.preferences
        self.ui_scale = prefs.view.ui_scale
        if hasattr(prefs.view, "gizmo_size_navigate_v3d"):
            self.gizmo_nav = prefs.view.gizmo_size_navigate_v3d
        if hasattr(prefs.view, "gizmo_size"):
            self.gizmo_size = prefs.view.gizmo_size
        space = getattr(context, "space_data", None)
        if space is not None and getattr(space, "type", "") == 'VIEW_3D':
            self.show_toolbar = space.show_region_toolbar
            self.show_sidebar = space.show_region_ui
            self.show_overlays = space.overlay.show_overlays
        return context.window_manager.invoke_props_dialog(self, width=380)

    def check(self, context):
        set_ui_scale(self.ui_scale, save=False)
        return True

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = False
        scale_box = layout.box()
        scale_box.label(text=f"UI Size  {ui_scale_percent()}%")
        row = scale_box.row(align=True)
        row.scale_y = 1.6
        smaller = row.operator("wm.android_ui_scale", text="Smaller")
        smaller.delta = -0.10
        smaller.value = 0.0
        larger = row.operator("wm.android_ui_scale", text="Larger")
        larger.delta = 0.10
        larger.value = 0.0
        presets = scale_box.row(align=True)
        presets.scale_y = 1.25
        for label, value in (("S", 1.20), ("M", 1.55), ("L", 1.90), ("XL", 2.30)):
            op = presets.operator("wm.android_ui_scale", text=label)
            op.value = value
            op.delta = 0.0
        scale_box.prop(self, "ui_scale", slider=True)
        col = layout.column(align=True)
        col.scale_y = 1.35
        col.prop(self, "gizmo_nav")
        col.prop(self, "gizmo_size")
        layout.separator()
        box = layout.box()
        box.scale_y = 1.25
        box.prop(self, "show_toolbar")
        box.prop(self, "show_sidebar")
        box.prop(self, "show_overlays")
        layout.separator()
        editors = layout.box()
        editors.label(text="Editors")
        editors.scale_y = 1.25
        row = editors.row(align=True)
        row.operator("wm.android_split_editor", text="Split Right").direction = 'VERTICAL'
        row.operator("wm.android_split_editor", text="Split Down").direction = 'HORIZONTAL'
        editors.operator("wm.android_close_editor", text="Close Editor")
        editors.operator("wm.android_apply_layout", text="Reset Editors")
        types = editors.row(align=True)
        for label, editor in (("3D", 'VIEW_3D'), ("Props", 'PROPERTIES'), ("Outliner", 'OUTLINER'), ("Image", 'IMAGE_EDITOR')):
            op = types.operator("wm.android_set_editor", text=label)
            op.editor_type = editor
        layout.separator()
        help_col = layout.column(align=True)
        layout.separator()
        files = layout.column(align=True)
        files.scale_y = 1.25
        files.operator("wm.android_open_file", icon='FILE_FOLDER')
        files.operator("wm.android_save_file", icon='FILE_TICK')
        files.operator("wm.android_browse_storage", icon='DISK_DRIVE')
        files.operator("wm.android_grant_files", icon='UNLOCKED')
        layout.separator()
        render_box = layout.box()
        render_box.scale_y = 1.25
        render_box.operator("wm.android_use_cycles", icon='SCENE')
        render_box.operator("render.render", text="Render Image", icon='RENDER_STILL')
        layout.separator()
        help_col = layout.column(align=True)
        help_col.label(text="Drag = orbit")
        help_col.label(text="Two fingers = pan")
        help_col.label(text="Pinch = zoom")
        help_col.label(text="Right-click = menu")
        help_col.label(text="Use the 3D widget to snap views")
        help_col.label(text="Drag the gray bars to resize editors")
        help_col.label(text="Drag a corner to split or join")

    def execute(self, context):
        prefs = context.preferences
        set_ui_scale(self.ui_scale, save=False)
        if hasattr(prefs.view, "gizmo_size_navigate_v3d"):
            prefs.view.gizmo_size_navigate_v3d = self.gizmo_nav
        if hasattr(prefs.view, "gizmo_size"):
            prefs.view.gizmo_size = self.gizmo_size
        apply_phone_prefs()
        apply_view3d_settings(toolbar=self.show_toolbar, sidebar=self.show_sidebar)
        for window in context.window_manager.windows:
            for area in window.screen.areas:
                if area.type != 'VIEW_3D':
                    continue
                space = area.spaces.active
                space.overlay.show_overlays = self.show_overlays
                space.show_region_toolbar = self.show_toolbar
                space.show_region_ui = self.show_sidebar
        try:
            bpy.ops.wm.save_userpref()
        except Exception:
            pass
        self.report({'INFO'}, "Phone settings saved")
        return {'FINISHED'}


class WM_OT_android_split_editor(Operator):
    bl_idname = "wm.android_split_editor"
    bl_label = "Split Editor"
    bl_description = "Split this editor so you can drag the bar between them"

    direction: EnumProperty(
        name="Direction",
        items=(
            ('VERTICAL', "Right", "Split a new editor to the right"),
            ('HORIZONTAL', "Down", "Split a new editor below"),
        ),
        default='VERTICAL',
    )

    def execute(self, context):
        window = context.window
        screen = context.screen
        area = context.area
        if window is None or screen is None or area is None:
            self.report({'ERROR'}, "No editor to split")
            return {'CANCELLED'}
        if area.type in {'TOPBAR', 'STATUSBAR'}:
            self.report({'ERROR'}, "Pick a 3D or side editor first")
            return {'CANCELLED'}
        _exit_area_fullscreen(window, screen)
        factor = 0.62 if self.direction == 'VERTICAL' else 0.70
        new_type = 'PROPERTIES' if self.direction == 'VERTICAL' else 'OUTLINER'
        if _split_content(window, screen, area, self.direction, factor, new_type) is None:
            self.report({'ERROR'}, "Could not split this editor")
            return {'CANCELLED'}
        self.report({'INFO'}, "Drag the gray bar to resize")
        return {'FINISHED'}


class WM_OT_android_close_editor(Operator):
    bl_idname = "wm.android_close_editor"
    bl_label = "Close Editor"
    bl_description = "Close this editor and give its space to the neighbor"

    def execute(self, context):
        area = context.area
        if area is None or area.type in {'TOPBAR', 'STATUSBAR', 'VIEW_3D'}:
            extras = []
            if context.screen is not None:
                extras = [item for item in _content_areas(context.screen) if item.type != 'VIEW_3D']
            area = extras[-1] if extras else None
        if area is None:
            self.report({'ERROR'}, "No extra editor to close")
            return {'CANCELLED'}
        try:
            with context.temp_override(window=context.window, screen=context.screen, area=area):
                bpy.ops.screen.area_close()
        except Exception:
            try:
                area.type = 'VIEW_3D'
            except Exception:
                self.report({'ERROR'}, "Could not close editor")
                return {'CANCELLED'}
        return {'FINISHED'}


class WM_OT_android_set_editor(Operator):
    bl_idname = "wm.android_set_editor"
    bl_label = "Set Editor"
    bl_description = "Change this editor type"

    editor_type: EnumProperty(
        name="Editor",
        items=(
            ('VIEW_3D', "3D Viewport", ""),
            ('PROPERTIES', "Properties", ""),
            ('OUTLINER', "Outliner", ""),
            ('IMAGE_EDITOR', "Image", ""),
            ('NODE_EDITOR', "Shader", ""),
            ('SEQUENCE_EDITOR', "Sequencer", ""),
            ('TEXT_EDITOR', "Text", ""),
            ('INFO', "Info", ""),
        ),
        default='PROPERTIES',
    )

    def execute(self, context):
        area = context.area
        if area is None or area.type in {'TOPBAR', 'STATUSBAR'}:
            extras = []
            if context.screen is not None:
                extras = [item for item in _content_areas(context.screen) if item.type != 'VIEW_3D']
            area = extras[-1] if extras else context.area
        if area is None or area.type in {'TOPBAR', 'STATUSBAR'}:
            self.report({'ERROR'}, "No editor selected")
            return {'CANCELLED'}
        try:
            area.type = self.editor_type
        except Exception:
            self.report({'ERROR'}, "Could not change editor")
            return {'CANCELLED'}
        return {'FINISHED'}


class WM_OT_android_use_cycles(Operator):
    bl_idname = "wm.android_use_cycles"
    bl_label = "Cycles (CPU)"
    bl_description = "Use Cycles on the phone CPU and show the result in this window"

    def execute(self, context):
        if hasattr(context.preferences.view, "render_display_type"):
            context.preferences.view.render_display_type = 'SCREEN'
        if not apply_cycles_cpu(set_engine=True):
            self.report({'ERROR'}, "Cycles is not in this build")
            return {'CANCELLED'}
        self.report({'INFO'}, "Cycles CPU ready — Render Image or F12")
        return {'FINISHED'}


class VIEW3D_PT_android_mobile(Panel):
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Phone"
    bl_label = "Phone"

    @classmethod
    def poll(cls, _context):
        return is_mobile()

    def draw(self, context):
        layout = self.layout
        layout.scale_y = 1.3
        layout.operator("wm.android_mobile_settings", icon='PREFERENCES')
        layout.operator("wm.android_apply_layout", icon='FULLSCREEN_ENTER')
        scale_box = layout.box()
        scale_box.label(text=f"UI Size  {ui_scale_percent()}%")
        row = scale_box.row(align=True)
        row.scale_y = 1.5
        smaller = row.operator("wm.android_ui_scale", text="Smaller")
        smaller.delta = -0.10
        smaller.value = 0.0
        larger = row.operator("wm.android_ui_scale", text="Larger")
        larger.delta = 0.10
        larger.value = 0.0
        scale_box.prop(context.preferences.view, "ui_scale", text="Scale", slider=True)
        presets = scale_box.row(align=True)
        for label, value in (("S", 1.20), ("M", 1.55), ("L", 1.90), ("XL", 2.30)):
            op = presets.operator("wm.android_ui_scale", text=label)
            op.value = value
            op.delta = 0.0
        layout.separator()
        layout.operator("wm.android_open_file", icon='FILE_FOLDER')
        layout.operator("wm.android_save_file", icon='FILE_TICK')
        layout.operator("wm.android_browse_storage", icon='DISK_DRIVE')
        layout.operator("wm.android_grant_files", icon='UNLOCKED')
        layout.operator("wm.android_use_cycles", icon='SCENE')
        layout.operator("render.render", text="Render Image", icon='RENDER_STILL')
        space = context.space_data
        box = layout.box()
        box.prop(space, "show_region_toolbar", text="Toolbar")
        box.prop(space, "show_region_ui", text="Sidebar")
        box.prop(space.overlay, "show_overlays", text="Overlays")
        layout.separator()
        row = layout.row(align=True)
        row.operator("wm.android_split_editor", text="Split Right").direction = 'VERTICAL'
        row.operator("wm.android_split_editor", text="Split Down").direction = 'HORIZONTAL'
        layout.operator("wm.android_close_editor", text="Close Editor")
        types = layout.row(align=True)
        for label, editor in (("3D", 'VIEW_3D'), ("Props", 'PROPERTIES'), ("Outliner", 'OUTLINER')):
            op = types.operator("wm.android_set_editor", text=label)
            op.editor_type = editor
        layout.separator()
        layout.label(text="Drag the gray bars to resize")


class VIEW3D_MT_android_phone(Menu):
    bl_label = "Phone"

    def draw(self, _context):
        layout = self.layout
        layout.operator("wm.android_mobile_settings", icon='PREFERENCES')
        layout.operator("wm.android_apply_layout", icon='FULLSCREEN_ENTER')
        layout.separator()
        smaller = layout.operator("wm.android_ui_scale", text="Smaller UI")
        smaller.delta = -0.10
        smaller.value = 0.0
        larger = layout.operator("wm.android_ui_scale", text="Larger UI")
        larger.delta = 0.10
        larger.value = 0.0
        layout.separator()
        layout.operator("wm.android_open_file", icon='FILE_FOLDER')
        layout.operator("wm.android_save_file", icon='FILE_TICK')
        layout.operator("wm.android_browse_storage", icon='DISK_DRIVE')
        layout.operator("wm.android_grant_files", icon='UNLOCKED')


_header_appended = False
_topbar_appended = False
_file_menu_appended = False


def draw_file_menu(self, _context):
    if not is_mobile():
        return
    self.layout.operator("wm.android_open_file", text="Open Project", icon='FILE_FOLDER')
    self.layout.separator()


def draw_view3d_header(self, _context):
    if not is_mobile():
        return
    row = self.layout.row(align=True)
    smaller = row.operator("wm.android_ui_scale", text="", icon='REMOVE')
    smaller.delta = -0.10
    smaller.value = 0.0
    row.label(text=f"{ui_scale_percent()}%")
    larger = row.operator("wm.android_ui_scale", text="", icon='ADD')
    larger.delta = 0.10
    larger.value = 0.0
    row.operator("wm.android_mobile_settings", text="", icon='PREFERENCES')
    row.menu("VIEW3D_MT_android_phone", text="Phone")


def draw_topbar(self, context):
    if not is_mobile():
        return
    if getattr(context.region, "alignment", "") != 'RIGHT':
        return
    row = self.layout.row(align=True)
    smaller = row.operator("wm.android_ui_scale", text="", icon='REMOVE')
    smaller.delta = -0.10
    smaller.value = 0.0
    larger = row.operator("wm.android_ui_scale", text="", icon='ADD')
    larger.delta = 0.10
    larger.value = 0.0
    row.operator("wm.android_open_file", text="Open", icon='FILE_FOLDER')
    row.operator("wm.android_mobile_settings", text="Phone", icon='PREFERENCES')


classes = (
    WM_OT_android_ui_scale,
    WM_OT_android_open_blend_path,
    WM_OT_android_open_file,
    WM_OT_android_save_file,
    WM_OT_android_browse_storage,
    WM_OT_android_grant_files,
    WM_OT_android_apply_layout,
    WM_OT_android_start,
    WM_OT_android_mobile_settings,
    WM_OT_android_split_editor,
    WM_OT_android_close_editor,
    WM_OT_android_set_editor,
    WM_OT_android_use_cycles,
    VIEW3D_PT_android_mobile,
    VIEW3D_MT_android_phone,
)


def register():
    global _header_appended, _topbar_appended, _file_menu_appended
    for cls in classes:
        bpy.utils.register_class(cls)
    if not is_mobile():
        return
    if not _header_appended:
        bpy.types.VIEW3D_HT_header.append(draw_view3d_header)
        _header_appended = True
    if not _topbar_appended:
        bpy.types.TOPBAR_HT_upper_bar.append(draw_topbar)
        _topbar_appended = True
    if not _file_menu_appended:
        bpy.types.TOPBAR_MT_file.prepend(draw_file_menu)
        _file_menu_appended = True
    if _on_file_load not in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.append(_on_file_load)
    try:
        bpy.app.timers.register(_poll_orientation, persistent=True, first_interval=1.0)
    except Exception:
        pass
    try:
        bpy.app.timers.register(_poll_file_bridge, persistent=True, first_interval=0.4)
    except Exception:
        pass
    try:
        apply_phone_prefs()
    except Exception:
        pass
    try:
        bpy.app.timers.register(_enable_cycles_later, first_interval=0.4)
    except Exception:
        pass


def unregister():
    global _header_appended, _topbar_appended, _file_menu_appended
    if _header_appended:
        try:
            bpy.types.VIEW3D_HT_header.remove(draw_view3d_header)
        except Exception:
            pass
        _header_appended = False
    if _topbar_appended:
        try:
            bpy.types.TOPBAR_HT_upper_bar.remove(draw_topbar)
        except Exception:
            pass
        _topbar_appended = False
    if _file_menu_appended:
        try:
            bpy.types.TOPBAR_MT_file.remove(draw_file_menu)
        except Exception:
            pass
        _file_menu_appended = False
    if _on_file_load in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.remove(_on_file_load)
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)
