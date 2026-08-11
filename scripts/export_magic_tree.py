from __future__ import annotations

import os
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[1]
GLB_PATH = ROOT / "build" / "magic_tree" / "magic_tree.raw.glb"
STANDIN_DIR = ROOT / "assets" / "tree_scene" / "standins"
AGE_KEYS = (0.08, 0.25, 0.48, 0.72, 1.0)
AGE_KEY_NAMES = ("age_00", "age_25", "age_48", "age_72", "age_100")
STANDIN_AGES = (0.08, 0.20, 0.40, 0.60, 0.80, 1.0)


def set_tree_age(age: float) -> None:
    tree = bpy.data.objects["TrunkSkinned"]
    targets = [tree, bpy.data.objects["Roots"]]
    targets.extend(
        leaf
        for group in range(6)
        if (leaf := bpy.data.objects.get(f"LeavesAge{group}")) is not None
    )
    for target in targets:
        blocks = target.data.shape_keys.key_blocks
        for name in AGE_KEY_NAMES:
            blocks[name].value = 0.0

    if age <= AGE_KEYS[0]:
        weights = {"age_00": 1.0}
    elif age >= AGE_KEYS[-1]:
        weights = {"age_100": 1.0}
    else:
        weights = {}
        for lower, upper in zip(AGE_KEYS, AGE_KEYS[1:]):
            if lower <= age <= upper:
                mix = (age - lower) / (upper - lower)
                lower_name = AGE_KEY_NAMES[AGE_KEYS.index(lower)]
                upper_name = AGE_KEY_NAMES[AGE_KEYS.index(upper)]
                weights = {lower_name: 1.0 - mix, upper_name: mix}
                break
    for target in targets:
        blocks = target.data.shape_keys.key_blocks
        for name, value in weights.items():
            blocks[name].value = value

    for group in range(6):
        leaf = bpy.data.objects.get(f"LeavesAge{group}")
        if leaf is not None:
            leaf.hide_render = group / 5 > age + 0.08
    veins = bpy.data.objects.get("MagicVeins")
    if veins is not None:
        veins.hide_render = age < 0.55


def render_standins() -> None:
    STANDIN_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    for animated in (
        bpy.data.objects.get("MagicTreeArmature"),
        bpy.data.objects["TrunkSkinned"].data.shape_keys,
    ):
        if animated is None or animated.animation_data is None:
            continue
        for track in animated.animation_data.nla_tracks:
            track.mute = True
    scene.frame_set(1)
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = True
    ground = bpy.data.objects.get("Ground")
    if ground is not None:
        ground.hide_render = True
    for index, age in enumerate(STANDIN_AGES):
        set_tree_age(age)
        camera = scene.camera
        camera.location.y = -29.5
        scene.render.filepath = str(STANDIN_DIR / f"age_{index}.webp")
        bpy.ops.render.render(write_still=True)
        print(f"回退图 age_{index} 已渲染，树龄 {age:.2f}")


def export_glb() -> None:
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    set_tree_age(1.0)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        excluded = bool(obj.get("export_exclude", False))
        if not excluded and obj.type not in {"CAMERA", "LIGHT"}:
            obj.hide_viewport = False
            obj.hide_render = False
            obj.select_set(True)

    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_skins=True,
        export_influence_nb=4,
        export_all_influences=False,
        export_def_bones=False,
        export_rest_position_armature=True,
        export_morph=True,
        export_morph_normal=True,
        export_morph_tangent=False,
        export_morph_animation=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=True,
        export_frame_step=1,
        export_force_sampling=True,
        export_optimize_animation_size=True,
        export_extras=True,
        export_apply=False,
        export_cameras=False,
        export_lights=False,
    )
    print(f"魔树 GLB 已导出：{GLB_PATH}")


def main() -> None:
    export_glb()
    if os.environ.get("MAGIC_TREE_SKIP_STANDINS") != "1":
        render_standins()


if __name__ == "__main__":
    main()
