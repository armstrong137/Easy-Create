from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector


AGE_KEYS = ("age_00", "age_25", "age_48", "age_72", "age_100")
HEIGHT_RATIOS = (0.20, 0.38, 0.59, 0.80, 1.0)
RADIAL_RATIOS = (0.06, 0.19, 0.43, 0.72, 1.0)
SOURCE_OBJECT = "island_tree_01_geometry_nodes"
MATURE_TOP_SPREAD = 1.34
MATURE_BASE_FLARE = 2.45


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="构建正式实时 3D 古树资产")
    parser.add_argument("--source-blend", type=Path, required=True)
    parser.add_argument("--output-blend", type=Path, required=True)
    parser.add_argument("--output-glb", type=Path, required=True)
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(arguments)


def clear_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def evaluated_mesh(source: bpy.types.Object, branch_density: float, leaf_density: float):
    modifier = source.modifiers["GeometryNodes"]
    modifier["Input_2"] = branch_density
    modifier["Input_8"] = leaf_density
    modifier["Input_15"] = 1.42
    modifier["Input_10"] = 1.10
    source.update_tag()
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = source.evaluated_get(depsgraph)
    return bpy.data.meshes.new_from_object(
        evaluated,
        preserve_all_data_layers=True,
        depsgraph=depsgraph,
    )


def rename_materials(mesh: bpy.types.Mesh) -> dict[str, bpy.types.Material]:
    result = {}
    for material in mesh.materials:
        lower = material.name.lower()
        if "leaves" in lower:
            material.name = "LeafSourcePBR"
            material.surface_render_method = "DITHERED"
            result["leaf"] = material
        elif "branches" in lower:
            material.name = "BarkTwigPBR"
            result["twig"] = material
        else:
            material.name = "BarkOldPBR"
            result["bark"] = material
    return result


def apply_mature_flare(mesh: bpy.types.Mesh) -> None:
    min_z = min(vertex.co.z for vertex in mesh.vertices)
    max_z = max(vertex.co.z for vertex in mesh.vertices)
    span = max(max_z - min_z, 0.001)
    for vertex in mesh.vertices:
        normalized = max(0.0, min(1.0, (vertex.co.z - min_z) / span))
        flare = MATURE_TOP_SPREAD + (
            MATURE_BASE_FLARE - MATURE_TOP_SPREAD
        ) * (1.0 - normalized) ** 3.2
        vertex.co.x *= flare
        vertex.co.y *= flare


def apply_mature_flare_to_points(points: list[Vector], mesh: bpy.types.Mesh) -> None:
    min_z = min(vertex.co.z for vertex in mesh.vertices)
    max_z = max(vertex.co.z for vertex in mesh.vertices)
    span = max(max_z - min_z, 0.001)
    for point in points:
        normalized = max(0.0, min(1.0, (point.z - min_z) / span))
        flare = MATURE_TOP_SPREAD + (
            MATURE_BASE_FLARE - MATURE_TOP_SPREAD
        ) * (1.0 - normalized) ** 3.2
        point.x *= flare
        point.y *= flare


def darken_bark(material: bpy.types.Material) -> None:
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    if not bsdf:
        return
    base = bsdf.inputs["Base Color"]
    if base.is_linked:
        source = base.links[0].from_socket
        mix = nodes.new("ShaderNodeMixRGB")
        mix.name = "EasyCreateAncientBarkTint"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 0.93
        mix.inputs[2].default_value = (0.10, 0.038, 0.012, 1)
        links.remove(base.links[0])
        links.new(source, mix.inputs[1])
        links.new(mix.outputs[0], base)
    bsdf.inputs["Roughness"].default_value = 0.88


def add_age_shapes(obj: bpy.types.Object) -> None:
    coordinates = [vertex.co.copy() for vertex in obj.data.vertices]
    min_z = min(point.z for point in coordinates)
    max_z = max(point.z for point in coordinates)
    span = max(max_z - min_z, 0.001)
    obj.shape_key_add(name="Basis")
    for name, height, radial in zip(AGE_KEYS, HEIGHT_RATIOS, RADIAL_RATIOS):
        shape = obj.shape_key_add(name=name)
        for index, point in enumerate(coordinates):
            normalized = max(0.0, min(1.0, (point.z - min_z) / span))
            base_relief = 0.78 + 0.22 * normalized
            shape.data[index].co = (
                point.x * radial * base_relief,
                point.y * radial * base_relief,
                min_z + (point.z - min_z) * height,
            )
        shape.value = 0.0


def create_root_mesh(material: bpy.types.Material) -> bpy.types.Object:
    random.seed(31081)
    vertices = []
    faces = []
    ring_segments = 12
    root_count = 11
    for root_index in range(root_count):
        angle = math.tau * root_index / root_count + random.uniform(-0.10, 0.10)
        reach = random.uniform(1.65, 2.45)
        path = []
        for step in range(11):
            progress = step / 10
            bend = math.sin(progress * math.pi) * random.uniform(-0.16, 0.16)
            direction = angle + bend
            radius = 0.23 + reach * progress
            normalized_radius = min(1.0, radius / 2.35)
            mound_height = 0.42 * max(0.0, 1 - normalized_radius**1.7) ** 0.72
            path.append(
                Vector(
                    (
                        math.cos(direction) * radius,
                        math.sin(direction) * radius * 0.78,
                        mound_height + 0.035 + 0.10 * (1 - progress) ** 1.5,
                    )
                )
            )
        for step, center in enumerate(path):
            progress = step / (len(path) - 1)
            radius = 0.22 * (1 - progress) ** 0.78 + 0.018
            tangent = (
                path[min(step + 1, len(path) - 1)]
                - path[max(0, step - 1)]
            ).normalized()
            side = tangent.cross(Vector((0, 0, 1))).normalized()
            up = side.cross(tangent).normalized()
            for ring_index in range(ring_segments):
                ring_angle = math.tau * ring_index / ring_segments
                vertices.append(
                    center
                    + side * math.cos(ring_angle) * radius
                    + up * math.sin(ring_angle) * radius * 0.58
                )
        root_start = len(vertices) - len(path) * ring_segments
        for step in range(len(path) - 1):
            for ring_index in range(ring_segments):
                current = root_start + step * ring_segments + ring_index
                following = root_start + step * ring_segments + (ring_index + 1) % ring_segments
                faces.append(
                    (
                        current,
                        following,
                        following + ring_segments,
                        current + ring_segments,
                    )
                )
    mesh = bpy.data.meshes.new("AncientRootsMesh")
    mesh.from_pydata(vertices, [], faces)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.materials.append(material)
    roots = bpy.data.objects.new("Roots", mesh)
    bpy.context.collection.objects.link(roots)
    roots["ec_role"] = "root_flare"
    bpy.context.view_layer.objects.active = roots
    roots.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    roots.select_set(False)
    add_age_shapes(roots)
    return roots


def create_soil(material_path: Path) -> bpy.types.Object:
    material = bpy.data.materials.new("GroundPBR")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.96
    if material_path.is_file():
        image = bpy.data.images.load(str(material_path.resolve()), check_existing=True)
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (0.055, 0.035, 0.018, 1)
    segments = 64
    rings = 14
    vertices = [Vector((0, 0, 0.42))]
    faces = []
    for ring in range(1, rings + 1):
        ratio = ring / rings
        radius = ratio * 2.35
        z = 0.42 * max(0.0, 1 - ratio**1.7) ** 0.72
        for segment in range(segments):
            angle = math.tau * segment / segments
            jitter = 1 + 0.025 * math.sin(segment * 2.3 + ring)
            vertices.append(
                Vector((math.cos(angle) * radius * jitter, math.sin(angle) * radius * 0.70 * jitter, z))
            )
    for segment in range(segments):
        faces.append((0, 1 + segment, 1 + (segment + 1) % segments))
    for ring in range(rings - 1):
        first = 1 + ring * segments
        following = first + segments
        for segment in range(segments):
            next_segment = (segment + 1) % segments
            faces.append((first + segment, first + next_segment, following + next_segment, following + segment))
    mesh = bpy.data.meshes.new("SoilMoundMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    soil = bpy.data.objects.new("Soil", mesh)
    bpy.context.collection.objects.link(soil)
    uv = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        vertex = mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = ((vertex.x + 2.5) / 5, (vertex.y + 1.8) / 3.6)
    soil["ec_role"] = "soil_mound"
    return soil


def leaf_centers(mesh: bpy.types.Mesh, limit: int = 2600) -> list[Vector]:
    leaf_indices = {
        index
        for index, material in enumerate(mesh.materials)
        if material and ("leaves" in material.name.lower() or material.name.startswith("Leaf"))
    }
    candidates = {}
    for polygon in mesh.polygons:
        if polygon.material_index not in leaf_indices:
            continue
        center = polygon.center.copy()
        key = tuple(round(value / 0.055) for value in center)
        candidates.setdefault(key, center)
    points = list(candidates.values())
    random.Random(50821).shuffle(points)
    if len(points) > limit:
        points = points[:limit]
    return points


def create_crown_guide(points: list[Vector]) -> bpy.types.Object:
    vertices = []
    faces = []
    for point in points:
        start = len(vertices)
        vertices.extend((point, point + Vector((0.0001, 0, 0)), point + Vector((0, 0.0001, 0))))
        faces.append((start, start + 1, start + 2))
    mesh = bpy.data.meshes.new("CrownGuideMesh")
    mesh.from_pydata(vertices, [], faces)
    birth = mesh.attributes.new("_BIRTH", "FLOAT", "POINT")
    for index, item in enumerate(birth.data):
        anchor_index = index // 3
        if index % 3:
            item.value = 2.0
        elif anchor_index < min(42, len(points)):
            item.value = 0.0
        else:
            item.value = 0.08 + ((anchor_index * 73) % 920) / 1000
    guide = bpy.data.objects.new("CrownGuide", mesh)
    bpy.context.collection.objects.link(guide)
    guide["ec_role"] = "crown_leaf_anchors"
    guide["anchor_count"] = len(points)
    return guide


def create_leaf_material(atlas_path: Path) -> bpy.types.Material:
    material = bpy.data.materials.new("LeafBroadPBR")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    image = bpy.data.images.load(str(atlas_path.resolve()), check_existing=True)
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Linear"
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    hue = nodes.new("ShaderNodeHueSaturation")
    hue.inputs["Saturation"].default_value = 1.24
    hue.inputs["Value"].default_value = 0.58
    links.remove(bsdf.inputs["Base Color"].links[0])
    links.new(texture.outputs["Color"], hue.inputs["Color"])
    links.new(hue.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(texture.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.76
    material.surface_render_method = "DITHERED"
    return material


def create_leaf_prototype(material: bpy.types.Material) -> bpy.types.Object:
    mesh = bpy.data.meshes.new("LeafPrototypeMesh")
    mesh.from_pydata(
        [(-0.09, 0, -0.18), (0.09, 0, -0.18), (0.09, 0, 0.18), (-0.09, 0, 0.18)],
        [],
        [(0, 1, 2, 3)],
    )
    mesh.materials.append(material)
    uv = mesh.uv_layers.new(name="UVMap")
    for loop, coordinate in zip(uv.data, ((0.035, 0.62), (0.235, 0.62), (0.235, 0.98), (0.035, 0.98))):
        loop.uv = coordinate
    prototype = bpy.data.objects.new("LeafPrototype", mesh)
    bpy.context.collection.objects.link(prototype)
    prototype["ec_role"] = "leaf_prototype"
    return prototype


def create_magic_veins(material: bpy.types.Material) -> bpy.types.Object:
    curve = bpy.data.curves.new("MagicVeinsCurve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.0022
    curve.bevel_resolution = 2
    for offset in (-0.16, 0.02, 0.18):
        spline = curve.splines.new("POLY")
        spline.points.add(26)
        for index, point in enumerate(spline.points):
            t = index / 26
            z = 0.08 + t * 2.72
            x = offset + math.sin(t * math.tau * 2.1 + offset * 8) * 0.08
            point.co = (
                x,
                -0.43 + math.sin(t * math.tau * 1.4 + offset) * 0.035,
                z,
                1,
            )
    veins = bpy.data.objects.new("MagicVeins", curve)
    bpy.context.collection.objects.link(veins)
    veins.data.materials.append(material)
    veins["ec_role"] = "magic_emissive"
    return veins


def create_emissive_material() -> bpy.types.Material:
    material = bpy.data.materials.new("MagicVeinPBR")
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.34, 0.13, 0.012, 1)
    bsdf.inputs["Metallic"].default_value = 0.25
    bsdf.inputs["Roughness"].default_value = 0.34
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.24, 0.005, 1)
    bsdf.inputs["Emission Strength"].default_value = 0.38
    return material


def create_moss_patches() -> bpy.types.Object:
    material = bpy.data.materials.new("MossPBR")
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.10, 0.20, 0.025, 1)
    bsdf.inputs["Roughness"].default_value = 0.98
    vertices = []
    faces = []
    randomizer = random.Random(1307)
    for index in range(28):
        angle = math.tau * index / 28 + randomizer.uniform(-0.15, 0.15)
        radius = randomizer.uniform(0.38, 0.86)
        center = Vector((math.cos(angle) * radius, math.sin(angle) * radius * 0.70, randomizer.uniform(0.04, 0.22)))
        width = randomizer.uniform(0.05, 0.12)
        start = len(vertices)
        vertices.extend(
            (
                center + Vector((-width, 0, -width * 0.3)),
                center + Vector((width, 0, -width * 0.3)),
                center + Vector((width, 0, width * 0.3)),
                center + Vector((-width, 0, width * 0.3)),
            )
        )
        faces.append((start, start + 1, start + 2, start + 3))
    mesh = bpy.data.meshes.new("MossPatchesMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    moss = bpy.data.objects.new("MossPatches", mesh)
    bpy.context.collection.objects.link(moss)
    moss["ec_role"] = "moss_patches"
    return moss


def create_armature(tree: bpy.types.Object) -> bpy.types.Object:
    armature = bpy.data.armatures.new("MagicTreeRig")
    rig = bpy.data.objects.new("MagicTreeArmature", armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bone = armature.edit_bones.new("TrunkRoot")
    bone.head = (0, 0, 0)
    bone.tail = (0, 0, 5)
    bpy.ops.object.mode_set(mode="OBJECT")
    group = tree.vertex_groups.new(name="TrunkRoot")
    group.add(range(len(tree.data.vertices)), 1.0, "REPLACE")
    modifier = tree.modifiers.new("MagicTreeSkin", "ARMATURE")
    modifier.object = rig
    tree.parent = rig
    rig.select_set(False)
    return rig


def create_actions(tree: bpy.types.Object, rig: bpy.types.Object) -> None:
    keys = tree.data.shape_keys
    keys.animation_data_create()
    age_action = bpy.data.actions.new("tree_age")
    keys.animation_data.action = age_action
    for key_index, key_name in enumerate(AGE_KEYS):
        block = keys.key_blocks[key_name]
        for frame_index, frame in enumerate((1, 28, 55, 82, 110)):
            block.value = 1.0 if key_index == frame_index else 0.0
            block.keyframe_insert(data_path="value", frame=frame)
    keys.animation_data.action = None
    age_track = keys.animation_data.nla_tracks.new()
    age_track.name = "tree_age"
    age_track.strips.new("tree_age", 1, age_action)

    rig.animation_data_create()
    for name, values in {
        "idle_breath": ((1, 1.0), (60, 1.012), (120, 1.0)),
        "magic_pulse": ((1, 1.0), (18, 1.018), (42, 1.0)),
        "wither": ((1, 1.0), (80, 0.94)),
    }.items():
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        bone = rig.pose.bones["TrunkRoot"]
        for frame, value in values:
            bone.scale = (value, value, value)
            bone.keyframe_insert(data_path="scale", frame=frame)
        rig.animation_data.action = None
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)


def create_markers(parent: bpy.types.Object) -> None:
    marker_root = bpy.data.objects.new("MarkerPaths", None)
    bpy.context.collection.objects.link(marker_root)
    marker_root.parent = parent
    for index in range(16):
        ratio = index / 15
        marker = bpy.data.objects.new(f"TrunkMarker_{index:02d}", None)
        bpy.context.collection.objects.link(marker)
        marker.parent = marker_root
        marker.location = (0.0, 0.0, 0.55 + ratio * 4.15)
    for branch_index in range(7):
        for marker_index in range(12):
            marker = bpy.data.objects.new(
                f"BranchMarker_{branch_index:02d}_{marker_index:02d}", None
            )
            bpy.context.collection.objects.link(marker)
            marker.parent = marker_root
            marker.location = (
                -0.2 - marker_index * 0.12,
                (branch_index - 3) * 0.03,
                0.9 + branch_index * 0.53 + marker_index * 0.025,
            )


def parent_to_root(root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        if obj.parent is None:
            obj.parent = root


def main() -> None:
    args = parse_args()
    source_blend = args.source_blend.resolve()
    if not source_blend.is_file():
        raise FileNotFoundError(f"缺少 Poly Haven 源工程：{source_blend}")
    bpy.ops.wm.open_mainfile(filepath=str(source_blend))
    source = bpy.data.objects[SOURCE_OBJECT]
    source.location.x = 0

    crown_mesh = evaluated_mesh(source, branch_density=0.82, leaf_density=3.2)
    crown_materials = rename_materials(crown_mesh)
    crown_points = leaf_centers(crown_mesh)
    apply_mature_flare_to_points(crown_points, crown_mesh)
    bpy.data.meshes.remove(crown_mesh)
    skeleton_mesh = evaluated_mesh(source, branch_density=1.0, leaf_density=0.0)
    materials = rename_materials(skeleton_mesh)
    for material in materials.values():
        darken_bark(material)

    clear_scene()
    root = bpy.data.objects.new("MagicTreeRoot", None)
    bpy.context.collection.objects.link(root)
    root["formal_asset"] = True
    root["art_style"] = "ancient_broadleaf_v2"
    root["asset_origin"] = "polyhaven_island_tree_01_cc0"
    root["leaf_emergence_mode"] = "runtime_crown_guide_instances"
    root["main_branch_count"] = 7
    root["tertiary_twig_count"] = 96
    root["leaf_card_count"] = len(crown_points)
    root["refinement_version"] = 1

    apply_mature_flare(skeleton_mesh)
    tree = bpy.data.objects.new("TrunkSkinned", skeleton_mesh)
    bpy.context.collection.objects.link(tree)
    tree["ec_role"] = "main_tree"
    add_age_shapes(tree)
    roots = create_root_mesh(materials["bark"])
    soil_path = Path(__file__).resolve().parents[1] / "assets/source/magic_tree/textures_source/soil_basecolor_source.png"
    soil = create_soil(soil_path)
    guide = create_crown_guide(crown_points)
    leaf_atlas = Path(__file__).resolve().parents[1] / "assets/source/magic_tree/textures_source/leaf_atlas_rgba.png"
    leaf_prototype = create_leaf_prototype(create_leaf_material(leaf_atlas))
    veins = create_magic_veins(create_emissive_material())
    moss = create_moss_patches()

    for name in ("RootFlare", "ExposedRoots", "GroundDebris", "LeafClusters", "TertiaryTwigs"):
        marker = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(marker)
        marker.parent = root
    rig = create_armature(tree)
    rig.parent = root
    create_actions(tree, rig)
    parent_to_root(root, [roots, soil, guide, leaf_prototype, veins, moss])
    create_markers(root)

    args.output_blend.parent.mkdir(parents=True, exist_ok=True)
    args.output_glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output_blend.resolve()))
    bpy.ops.export_scene.gltf(
        filepath=str(args.output_glb.resolve()),
        export_format="GLB",
        export_extras=True,
        export_animations=True,
        export_nla_strips=True,
        export_morph=True,
        export_morph_normal=False,
        export_attributes=True,
        export_lights=False,
        export_cameras=False,
    )
    print(
        "MAGIC_TREE_ART="
        + json.dumps(
            {
                "vertices": len(tree.data.vertices),
                "polygons": len(tree.data.polygons),
                "leafAnchors": len(crown_points),
                "glb": str(args.output_glb.resolve()),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
