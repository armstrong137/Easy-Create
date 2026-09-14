from __future__ import annotations

import argparse
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector


AGE_KEYS = ("age_00", "age_25", "age_48", "age_72", "age_100")
AGES = (0.0, 0.25, 0.48, 0.72, 1.0)
HEIGHT_RATIOS = (0.20, 0.38, 0.59, 0.80, 1.0)
RADIAL_RATIOS = (0.06, 0.19, 0.43, 0.72, 1.0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="渲染正式魔树五阶段视觉验收图")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--standin-dir", type=Path)
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(arguments)


def age_weights(age: float) -> tuple[dict[str, float], float, float]:
    bounded = max(0.0, min(1.0, age))
    if bounded <= AGES[0]:
        return {AGE_KEYS[0]: 1.0}, HEIGHT_RATIOS[0], RADIAL_RATIOS[0]
    if bounded >= AGES[-1]:
        return {AGE_KEYS[-1]: 1.0}, HEIGHT_RATIOS[-1], RADIAL_RATIOS[-1]
    for index in range(len(AGES) - 1):
        lower = AGES[index]
        upper = AGES[index + 1]
        if bounded <= upper:
            mix = (bounded - lower) / (upper - lower)
            return (
                {AGE_KEYS[index]: 1 - mix, AGE_KEYS[index + 1]: mix},
                HEIGHT_RATIOS[index] * (1 - mix) + HEIGHT_RATIOS[index + 1] * mix,
                RADIAL_RATIOS[index] * (1 - mix) + RADIAL_RATIOS[index + 1] * mix,
            )
    raise AssertionError("无法计算树龄权重")


def set_age(age: float) -> tuple[float, float]:
    weights, height, radial = age_weights(age)
    for name in ("TrunkSkinned", "Roots"):
        obj = bpy.data.objects[name]
        blocks = obj.data.shape_keys.key_blocks
        for key in AGE_KEYS:
            blocks[key].value = 0.0
        for key, value in weights.items():
            blocks[key].value = value
    return height, radial


def rebuild_preview_leaves(age: float, height: float, radial: float) -> None:
    previous = bpy.data.objects.get("PreviewLeaves")
    if previous:
        bpy.data.objects.remove(previous, do_unlink=True)
    guide = bpy.data.objects["CrownGuide"]
    position = guide.data.attributes["position"].data
    birth = guide.data.attributes["_BIRTH"].data
    size = 0.043 + age * 0.010
    vertices = []
    faces = []
    randomizer = random.Random(8127)
    leaf_specs = (
        (0.000, 0.028, 0.000, 1.00, 1.00),
        (-0.025, 0.010, 0.520, 0.91, 0.88),
        (0.025, 0.010, -0.520, 0.91, 0.88),
        (-0.040, -0.020, 0.780, 0.82, 0.79),
        (0.040, -0.020, -0.780, 0.82, 0.79),
    )
    for anchor_index, index in enumerate(range(0, len(position), 3)):
        if birth[index].value > age + 0.001:
            continue
        if anchor_index >= 42 and (anchor_index * 37) % 100 >= 65:
            continue
        source = Vector(position[index].vector)
        center = Vector((source.x * radial, source.y * radial, source.z * height))
        angle = randomizer.uniform(-math.pi, math.pi)
        depth = randomizer.uniform(-0.36, 0.36)
        cluster_side = Vector((math.cos(angle), depth, math.sin(angle))).normalized()
        normal = Vector(
            (
                randomizer.uniform(-0.25, 0.25),
                -1,
                randomizer.uniform(-0.18, 0.18),
            )
        ).normalized()
        cluster_up = normal.cross(cluster_side).normalized()
        for cluster_index in range(5):
            offset_x, offset_y, rotation, width_scale, height_scale = leaf_specs[cluster_index]
            leaf_side = (
                cluster_side * math.cos(rotation) + cluster_up * math.sin(rotation)
            ).normalized() * size * 0.40 * width_scale
            leaf_up = (
                cluster_up * math.cos(rotation) - cluster_side * math.sin(rotation)
            ).normalized() * size * 0.98 * height_scale
            offset = cluster_side * offset_x + cluster_up * offset_y
            start = len(vertices)
            vertices.extend(
                (
                    center + offset - leaf_side - leaf_up,
                    center + offset + leaf_side - leaf_up,
                    center + offset + leaf_side + leaf_up,
                    center + offset - leaf_side + leaf_up,
                )
            )
            faces.append((start, start + 1, start + 2, start + 3))
    mesh = bpy.data.meshes.new("PreviewLeavesMesh")
    mesh.from_pydata(vertices, [], faces)
    leaf_material = next(
        material
        for material in bpy.data.materials
        if material.name.startswith("LeafBroadPBR")
    )
    mesh.materials.append(leaf_material)
    uv = mesh.uv_layers.new(name="UVMap")
    coordinates = ((0.035, 0.62), (0.235, 0.62), (0.235, 0.98), (0.035, 0.98))
    for loop in mesh.loops:
        uv.data[loop.index].uv = coordinates[loop.vertex_index % 4]
    leaves = bpy.data.objects.new("PreviewLeaves", mesh)
    bpy.context.collection.objects.link(leaves)


def add_lighting() -> None:
    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.985, 0.93, 0.82, 1)
    background.inputs["Strength"].default_value = 0.82
    for location, energy, size, color in (
        ((-4.6, -5.2, 9.0), 1280, 4.8, (1.0, 0.68, 0.30)),
        ((4.8, -1.0, 7.0), 480, 4.0, (0.58, 0.78, 0.46)),
        ((0.0, 4.0, 8.0), 720, 3.6, (0.92, 0.82, 0.54)),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color


def aim_camera(location: tuple[float, float, float], target: tuple[float, float, float]):
    camera = bpy.data.objects.get("PreviewCamera")
    if not camera:
        bpy.ops.object.camera_add()
        camera = bpy.context.object
        camera.name = "PreviewCamera"
        camera.data.lens = 52
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    return camera


def main() -> None:
    args = parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name in ("CrownGuide", "LeafPrototype"):
        bpy.data.objects[name].hide_render = True
    bpy.data.objects["Soil"].hide_render = True
    bpy.data.objects["MossPatches"].hide_render = True
    rig = bpy.data.objects.get("MagicTreeArmature")
    if rig and rig.animation_data:
        for track in rig.animation_data.nla_tracks:
            track.mute = True
    keys = bpy.data.objects["TrunkSkinned"].data.shape_keys
    if keys.animation_data:
        for track in keys.animation_data.nla_tracks:
            track.mute = True
    add_lighting()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1400
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.view_settings.look = "Medium High Contrast"
    aim_camera((0, -11.4, 2.55), (0, 0, 2.35))
    for age_index in range(5):
        age = AGES[age_index]
        height, radial = set_age(age)
        rebuild_preview_leaves(age, height, radial)
        bpy.data.objects["MagicVeins"].hide_render = age_index < 3
        scene.render.filepath = str(output / f"stage_{age_index + 1}.png")
        bpy.ops.render.render(write_still=True)
    height, radial = set_age(1.0)
    rebuild_preview_leaves(1.0, height, radial)
    scene.render.resolution_x = 430
    scene.render.resolution_y = 932
    aim_camera((0, -5.6, 2.15), (0, 0, 2.15))
    scene.render.filepath = str(output / "mature_mobile.png")
    bpy.ops.render.render(write_still=True)
    if args.standin_dir:
        standins = args.standin_dir.resolve()
        standins.mkdir(parents=True, exist_ok=True)
        scene.render.resolution_x = 900
        scene.render.resolution_y = 1400
        scene.render.image_settings.file_format = "WEBP"
        scene.render.image_settings.color_mode = "RGBA"
        scene.render.film_transparent = True
        aim_camera((0, -11.4, 2.55), (0, 0, 2.35))
        for index, age in enumerate((0.0, 0.2, 0.4, 0.6, 0.8, 1.0)):
            height, radial = set_age(age)
            rebuild_preview_leaves(age, height, radial)
            bpy.data.objects["MagicVeins"].hide_render = age < 0.55
            scene.render.filepath = str(standins / f"age_{index}.webp")
            bpy.ops.render.render(write_still=True)
    print(f"MAGIC_TREE_PREVIEWS={output}")


if __name__ == "__main__":
    main()
