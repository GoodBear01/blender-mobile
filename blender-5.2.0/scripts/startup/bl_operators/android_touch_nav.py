# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later

"""Phone keymaps: keep right-click menus, do not steal the 3D widget."""

from __future__ import annotations

import bpy

from bl_operators.android_phone import is_mobile

_NAV_OPS = {
    "view3d.rotate",
    "view3d.move",
    "view3d.zoom",
    "view3d.dolly",
    "view3d.android_orbit",
    "view3d.android_pan",
}


class VIEW3D_OT_android_orbit(bpy.types.Operator):
    """Kept so old keymaps do not crash; navigation is handled in C++."""

    bl_idname = "view3d.android_orbit"
    bl_label = "Android Orbit"
    bl_options = {'INTERNAL'}

    def invoke(self, _context, _event):
        return {'CANCELLED', 'PASS_THROUGH'}


class VIEW3D_OT_android_pan(bpy.types.Operator):
    """Kept so old keymaps do not crash; navigation is handled in C++."""

    bl_idname = "view3d.android_pan"
    bl_label = "Android Pan"
    bl_options = {'INTERNAL'}

    def invoke(self, _context, _event):
        return {'CANCELLED', 'PASS_THROUGH'}


def _quiet_left_press_select(kc) -> None:
    if kc is None:
        return
    for km in kc.keymaps:
        name = km.name
        if name != "3D View" and not name.startswith("3D View Tool:"):
            continue
        for kmi in km.keymap_items:
            if kmi.idname in {"view3d.android_orbit", "view3d.android_pan"}:
                kmi.active = False
                continue
            if kmi.type == 'RIGHTMOUSE':
                kmi.active = True
                continue
            if kmi.type in {'TRACKPADPAN', 'MOUSEPAN'} and kmi.idname == "view3d.rotate":
                kmi.active = False
                continue
            if kmi.type != 'LEFTMOUSE':
                continue
            if kmi.shift or kmi.ctrl or kmi.alt or kmi.oskey:
                continue
            if kmi.idname in _NAV_OPS:
                kmi.active = False
                continue
            if kmi.value == 'PRESS':
                kmi.active = False


def _ensure_nav_items(km) -> None:
    for kmi in list(km.keymap_items):
        if kmi.idname in {"view3d.android_orbit", "view3d.android_pan"}:
            km.keymap_items.remove(kmi)
    if not any(kmi.idname == "view3d.select" and kmi.type == 'LEFTMOUSE' and kmi.value == 'CLICK'
               for kmi in km.keymap_items):
        km.keymap_items.new("view3d.select", "LEFTMOUSE", "CLICK")


def ensure_view3d_touch_keymap() -> None:
    if not is_mobile():
        return
    wm = bpy.context.window_manager
    if wm is None:
        return

    for kc in (wm.keyconfigs.default, wm.keyconfigs.user, wm.keyconfigs.active):
        _quiet_left_press_select(kc)
        if kc is None:
            continue
        for km in kc.keymaps:
            for kmi in km.keymap_items:
                if kmi.type == 'RIGHTMOUSE':
                    kmi.active = True

    kc_addon = wm.keyconfigs.addon
    if kc_addon is None:
        return
    km = kc_addon.keymaps.get("3D View")
    if km is None:
        km = kc_addon.keymaps.new("3D View", space_type='VIEW_3D', region_type='WINDOW')
    _ensure_nav_items(km)
    file_km = kc_addon.keymaps.get("File Browser Main")
    if file_km is None:
        file_km = kc_addon.keymaps.new(
            "File Browser Main", space_type='FILE_BROWSER', region_type='WINDOW'
        )
    if not any(
        kmi.idname == "file.mouse_execute" and kmi.type == 'LEFTMOUSE' and kmi.value == 'CLICK'
        for kmi in file_km.keymap_items
    ):
        file_km.keymap_items.new("file.mouse_execute", "LEFTMOUSE", "CLICK")
    for kmi in list(file_km.keymap_items):
        if kmi.idname == "file.mouse_execute" and kmi.type == 'LEFTMOUSE' and kmi.value == 'RELEASE':
            file_km.keymap_items.remove(kmi)


classes = (
    VIEW3D_OT_android_orbit,
    VIEW3D_OT_android_pan,
)


def register():
    if is_mobile():
        ensure_view3d_touch_keymap()


def unregister():
    pass
