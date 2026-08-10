from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
BLEND_PATH = (
    ROOT
    / "assets"
    / "source"
    / "magic_tree"
    / "blender"
    / "magic_tree_master.blend"
)
PBR = (
    ROOT
    / "assets"
    / "source"
    / "magic_tree"
    / "textures_source"
    / "pbr"
)
AGES = (0.08, 0.25, 0.48, 0.72, 1.0)
AGE_KEY_NAMES = ("age_00", "age_25", "age_48", "age_72", "age_100")
HEIGHT_RATIOS = (0.19, 0.34, 0.57, 0.79, 1.0)
WIDTH_RATIOS = (0.09, 0.22, 0.48, 0.75, 1.0)
RADIAL_SEGMENTS = 14
TREE_HEIGHT = 8.0
TRUNK_BASE_Z = 0.18


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material_with_pbr(name: str, prefix: str) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Roughness"].default_value = 0.72
    principled.inputs["Specular IOR Level"].default_value = 0.32
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])

    base = nodes.new("ShaderNodeTexImage")
    base.image = bpy.data.images.load(str(PBR / f"{prefix}_basecolor.png"))
    base.image.colorspace_settings.name = "sRGB"
    links.new(base.outputs["Color"], principled.inputs["Base Color"])

    rough = nodes.new("ShaderNodeTexImage")
    rough.image = bpy.data.images.load(str(PBR / f"{prefix}_roughness.png"))
    rough.image.colorspace_settings.name = "Non-Color"
    links.new(rough.outputs["Color"], principled.inputs["Roughness"])

    normal_texture = nodes.new("ShaderNodeTexImage")
    normal_texture.image = bpy.data.images.load(str(PBR / f"{prefix}_normal.png"))
    normal_texture.image.colorspace_settings.name = "Non-Color"
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.72 if prefix == "bark_old" else 0.45
    links.new(normal_texture.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    return material


def leaf_material(name: str, color: tuple[float, float, float]) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color, 1)
    principled.inputs["Roughness"].default_value = 0.57
    principled.inputs["Specular IOR Level"].default_value = 0.28
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(PBR / "leaf_single.png"), check_existing=True)
    texture.image.colorspace_settings.name = "sRGB"
    tint = material.node_tree.nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 0.28
    tint.inputs[2].default_value = (*color, 1)
    material.node_tree.links.new(texture.outputs["Color"], tint.inputs[1])
    material.node_tree.links.new(tint.outputs["Color"], principled.inputs["Base Color"])
    material.node_tree.links.new(texture.outputs["Alpha"], principled.inputs["Alpha"])
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    return material


def magic_material() -> bpy.types.Material:
    material = bpy.data.materials.new("MagicVein")
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (0.18, 0.36, 0.02, 1)
    principled.inputs["Emission Color"].default_value = (0.28, 0.62, 0.03, 1)
    principled.inputs["Emission Strength"].default_value = 0.45
    principled.inputs["Roughness"].default_value = 0.48
    return material


def trunk_path() -> list[Vector]:
    points = []
    for index in range(35):
        t = index / 34
        points.append(
            Vector(
                (
                    0.12 * math.sin(t * math.pi * 2.1) * (0.3 + t),
                    0.09 * math.sin(t * math.pi * 3.2 + 0.7),
                    TRUNK_BASE_Z + (6.15 - TRUNK_BASE_Z) * t,
                )
            )
        )
    return points


def branch_paths(trunk: list[Vector]) -> list[list[Vector]]:
    paths = []
    starts = (0.29, 0.36, 0.43, 0.50, 0.57, 0.64, 0.70, 0.75, 0.80)
    lengths = (2.78, 3.10, 3.02, 2.64, 2.82, 2.66, 2.48, 2.30, 2.08)
    for branch_index, (start, length) in enumerate(zip(starts, lengths)):
        root = trunk[round(start * (len(trunk) - 1))].copy()
        angle = branch_index * 2.31 + (0.20 if branch_index % 2 else -0.10)
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        upward = 0.34 + 0.025 * branch_index
        points = []
        for segment in range(14):
            u = segment / 13
            lateral = direction * length * (u ** 0.78)
            sweep = (
                Vector((-direction.y, direction.x, 0))
                * math.sin(u * math.pi)
                * (0.24 + 0.035 * branch_index)
            )
            rise = Vector((0, 0, length * (0.12 * u + upward * u * u)))
            points.append(root + lateral + sweep + rise)
        paths.append(points)
    return paths


def secondary_branch_paths(
    branches: list[list[Vector]],
) -> list[tuple[int, list[Vector]]]:
    secondary = []
    for parent_index, parent in enumerate(branches):
        parent_direction = (parent[-1] - parent[0]).normalized()
        for fork_index, start_index in enumerate((3, 5, 7, 9, 11, 12)):
            root = parent[start_index].copy()
            side = Vector((-parent_direction.y, parent_direction.x, 0)).normalized()
            sign = -1 if (parent_index + fork_index) % 2 else 1
            direction = (
                parent_direction * 0.42
                + side * sign * (0.82 - 0.04 * fork_index)
                + Vector((0, 0, 0.30 + 0.025 * fork_index))
            ).normalized()
            length = 1.34 - fork_index * 0.075 + 0.08 * math.sin(parent_index)
            path = []
            for segment in range(8):
                u = segment / 7
                path.append(
                    root
                    + direction * length * (u ** 0.82)
                    + Vector((0, 0, 0.14 * math.sin(u * math.pi)))
                )
            secondary.append((parent_index, path))
    return secondary


def frame_for_path(path: list[Vector], index: int) -> tuple[Vector, Vector]:
    if index == 0:
        tangent = (path[1] - path[0]).normalized()
    elif index == len(path) - 1:
        tangent = (path[-1] - path[-2]).normalized()
    else:
        tangent = (path[index + 1] - path[index - 1]).normalized()
    reference = Vector((0, 1, 0))
    if abs(tangent.dot(reference)) > 0.92:
        reference = Vector((1, 0, 0))
    normal = tangent.cross(reference).normalized()
    binormal = tangent.cross(normal).normalized()
    return normal, binormal


def append_tube(
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    uvs: list[tuple[float, float]],
    metadata: list[dict],
    path: list[Vector],
    radius_at,
    kind: str,
    branch_index: int = -1,
    root_override: Vector | None = None,
) -> None:
    start_vertex = len(vertices)
    root = (root_override or path[0]).copy()
    for path_index, center in enumerate(path):
        t = path_index / (len(path) - 1)
        normal, binormal = frame_for_path(path, path_index)
        radius = radius_at(t)
        for radial in range(RADIAL_SEGMENTS):
            angle = math.tau * radial / RADIAL_SEGMENTS
            bark = 1.0 + 0.055 * math.sin(angle * 5 + t * 18)
            point = center + (normal * math.cos(angle) + binormal * math.sin(angle)) * radius * bark
            vertices.append(tuple(point))
            uvs.append((radial / RADIAL_SEGMENTS, t * (5.0 if kind == "trunk" else 2.2)))
            metadata.append(
                {
                    "kind": kind,
                    "branch": branch_index,
                    "t": t,
                    "root": root.copy(),
                    "original": point.copy(),
                }
            )
    rings = len(path)
    for ring in range(rings - 1):
        for radial in range(RADIAL_SEGMENTS):
            next_radial = (radial + 1) % RADIAL_SEGMENTS
            a = start_vertex + ring * RADIAL_SEGMENTS + radial
            b = start_vertex + ring * RADIAL_SEGMENTS + next_radial
            c = start_vertex + (ring + 1) * RADIAL_SEGMENTS + next_radial
            d = start_vertex + (ring + 1) * RADIAL_SEGMENTS + radial
            faces.append((a, b, c, d))
    faces.append(tuple(start_vertex + radial for radial in reversed(range(RADIAL_SEGMENTS))))
    last = start_vertex + (rings - 1) * RADIAL_SEGMENTS
    faces.append(tuple(last + radial for radial in range(RADIAL_SEGMENTS)))


def create_trunk_and_branches(
    root: bpy.types.Object,
    bark: bpy.types.Material,
) -> tuple[
    bpy.types.Object,
    list[Vector],
    list[list[Vector]],
    list[tuple[int, list[Vector]]],
    list[dict],
]:
    trunk = trunk_path()
    branches = branch_paths(trunk)
    secondary = secondary_branch_paths(branches)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    uvs: list[tuple[float, float]] = []
    metadata: list[dict] = []

    append_tube(
        vertices,
        faces,
        uvs,
        metadata,
        trunk,
        lambda t: 0.025 + 0.69 * ((1 - t) ** 0.72) + 0.22 * math.exp(-t * 15),
        "trunk",
    )
    for branch_index, path in enumerate(branches):
        start_radius = 0.29 - branch_index * 0.018
        append_tube(
            vertices,
            faces,
            uvs,
            metadata,
            path,
            lambda t, radius=start_radius: 0.014 + radius * ((1 - t) ** 0.88),
            "branch",
            branch_index,
        )
    for parent_index, path in secondary:
        append_tube(
            vertices,
            faces,
            uvs,
            metadata,
            path,
            lambda t: 0.020 + 0.135 * ((1 - t) ** 0.92),
            "branch",
            parent_index,
            branches[parent_index][0],
        )

    mesh = bpy.data.meshes.new("TrunkSkinnedMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]

    tree = bpy.data.objects.new("TrunkSkinned", mesh)
    bpy.context.collection.objects.link(tree)
    tree.parent = root
    tree.data.materials.append(bark)
    tree["ec_role"] = "main_tree"
    tree["ec_schema_version"] = 1

    tree.shape_key_add(name="Basis")
    for age_index, (name, age, height, width) in enumerate(
        zip(AGE_KEY_NAMES, AGES, HEIGHT_RATIOS, WIDTH_RATIOS)
    ):
        shape = tree.shape_key_add(name=name)
        for vertex_index, item in enumerate(metadata):
            original = item["original"]
            if item["kind"] == "trunk":
                shaped = Vector(
                    (
                        original.x * width,
                        original.y * width,
                        TRUNK_BASE_Z + (original.z - TRUNK_BASE_Z) * height,
                    )
                )
            else:
                branch_index = item["branch"]
                root_mature = item["root"]
                root_age = Vector(
                    (
                        root_mature.x * width,
                        root_mature.y * width,
                        TRUNK_BASE_Z + (root_mature.z - TRUNK_BASE_Z) * height,
                    )
                )
                threshold = 0.05 + branch_index * 0.045
                branch_growth = max(
                    0.18,
                    min(1.0, (age - threshold + 0.12) / 0.42),
                )
                crown_width = 0.38 + width * 0.62
                local = original - root_mature
                shaped = root_age + Vector(
                    (
                        local.x * branch_growth * crown_width,
                        local.y * branch_growth * crown_width,
                        local.z * branch_growth * height,
                    )
                )
            shape.data[vertex_index].co = shaped
        shape.value = 0.0
    return tree, trunk, branches, secondary, metadata


def create_mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    material: bpy.types.Material,
    root: bpy.types.Object,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    obj.parent = root
    return obj


def create_roots(root: bpy.types.Object, bark: bpy.types.Material) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    uvs: list[tuple[float, float]] = []
    metadata: list[dict] = []
    for index in range(10):
        angle = math.tau * index / 10 + 0.2 * math.sin(index)
        length = 2.15 + 0.42 * math.sin(index * 1.7)
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        path = []
        for segment in range(9):
            t = segment / 8
            path.append(
                Vector((0, 0, 0.25))
                + direction * length * (t ** 0.72)
                + Vector((0, 0, -0.32 * t + 0.08 * math.sin(t * math.pi)))
            )
        append_tube(
            vertices,
            faces,
            uvs,
            metadata,
            path,
            lambda t: 0.035 + 0.26 * ((1 - t) ** 1.3),
            "root",
            index,
        )
    roots = create_mesh_object("Roots", vertices, faces, bark, root)
    uv_layer = roots.data.uv_layers.new(name="UVMap")
    for loop in roots.data.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    roots["ec_role"] = "roots"
    roots.shape_key_add(name="Basis")
    for name, age, width in zip(AGE_KEY_NAMES, AGES, WIDTH_RATIOS):
        shape = roots.shape_key_add(name=name)
        root_scale = 0.20 + width * 0.80
        for vertex_index, vertex in enumerate(roots.data.vertices):
            original = vertex.co
            shape.data[vertex_index].co = Vector(
                (original.x * root_scale, original.y * root_scale, original.z * root_scale)
            )
        shape.value = 0.0
    return roots


def create_soil(root: bpy.types.Object, material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=24, location=(0, 0, -0.28))
    soil = bpy.context.object
    soil.name = "Soil"
    soil.scale = (2.35, 1.72, 0.50)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for vertex in soil.data.vertices:
        radius = math.hypot(vertex.co.x / 2.35, vertex.co.y / 1.72)
        irregularity = (
            0.11 * math.sin(vertex.co.x * 4.7)
            + 0.07 * math.sin(vertex.co.y * 6.1 + 0.8)
        )
        vertex.co.z += irregularity * max(0, 1 - radius) ** 1.4
    soil.data.materials.append(material)
    soil.parent = root
    soil["ec_role"] = "soil"
    return soil


def append_leaf(
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    metadata: list[dict],
    center: Vector,
    direction: Vector,
    width: float,
    length: float,
    root: Vector,
    branch_index: int,
) -> None:
    forward = direction.normalized()
    # Flutter 场景从 Blender 的 -Y 方向观察，叶面需保留朝向镜头的可读面积。
    view_direction = Vector((0, -1, 0))
    side = forward.cross(view_direction)
    if side.length < 0.1:
        side = Vector((1, 0, 0))
    side.normalize()
    start = len(vertices)
    points = (
        center - forward * length * 0.48 - side * width,
        center - forward * length * 0.48 + side * width,
        center + forward * length * 0.52 + side * width,
        center + forward * length * 0.52 - side * width,
    )
    vertices.extend(tuple(point) for point in points)
    metadata.extend(
        {
            "branch": branch_index,
            "root": root.copy(),
            "center": center.copy(),
            "original": point.copy(),
        }
        for point in points
    )
    faces.append((start, start + 1, start + 2, start + 3))


def create_leaf_groups(
    root: bpy.types.Object,
    trunk: list[Vector],
    branches: list[list[Vector]],
    secondary: list[tuple[int, list[Vector]]],
    materials: list[bpy.types.Material],
) -> list[bpy.types.Object]:
    random.seed(40721)
    groups = [([], [], []) for _ in range(6)]
    seed_vertices, seed_faces, seed_meta = groups[0]
    for cluster_index, trunk_index in enumerate((24, 29, 34)):
        seed_center = trunk[trunk_index]
        count = 6 if cluster_index < 2 else 9
        for leaf_index in range(count):
            angle = math.tau * leaf_index / count + 0.18 * math.sin(leaf_index)
            radial = Vector((math.cos(angle), math.sin(angle), 0))
            center = seed_center + radial * 0.13 + Vector(
                (0, 0, 0.06 * math.sin(angle * 2))
            )
            direction = (radial * 0.72 + Vector((0, 0, 0.69))).normalized()
            append_leaf(
                seed_vertices,
                seed_faces,
                seed_meta,
                center,
                direction,
                0.16,
                0.42,
                Vector((0, 0, TRUNK_BASE_Z)),
                -1,
            )

    foliage_paths = [(index, path, False) for index, path in enumerate(branches)] + [
        (index, path, True) for index, path in secondary
    ]
    for branch_index, path, is_secondary in foliage_paths:
        cluster_points = (2, 4, 6, 7) if is_secondary else (4, 6, 8, 10, 12, 13)
        for path_index in cluster_points:
            centerline = path[path_index]
            tangent = (path[path_index] - path[path_index - 1]).normalized()
            count = 8 if path_index < len(path) - 1 else 10
            for leaf_index in range(count):
                angle = math.tau * leaf_index / count + random.uniform(-0.16, 0.16)
                radial = Vector(
                    (math.cos(angle), math.sin(angle), 0.30 + random.uniform(-0.10, 0.20))
                ).normalized()
                direction = (radial * 0.82 + tangent * 0.18).normalized()
                center = centerline + direction * (0.12 + 0.035 * (leaf_index % 3))
                branch_birth = 0.05 + branch_index * 0.045
                base_group = max(0, math.floor(branch_birth * 5))
                threshold = min(5, base_group + path_index // 4)
                vertices, faces, leaf_meta = groups[threshold]
                leaf_root = branches[branch_index][0] if is_secondary else path[0]
                append_leaf(
                    vertices,
                    faces,
                    leaf_meta,
                    center,
                    direction,
                    0.15 if is_secondary else 0.17,
                    0.38 if is_secondary else 0.43,
                    leaf_root,
                    branch_index,
                )

    objects = []
    for age_group, (vertices, faces, leaf_meta) in enumerate(groups):
        obj = create_mesh_object(
            f"LeavesAge{age_group}", vertices, faces, materials[0], root
        )
        for material in materials[1:]:
            obj.data.materials.append(material)
        for polygon in obj.data.polygons:
            polygon.material_index = (polygon.index + age_group) % len(materials)
        uv_layer = obj.data.uv_layers.new(name="UVMap")
        for loop in obj.data.loops:
            local_index = loop.vertex_index % 4
            uv = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))[local_index]
            uv_layer.data[loop.index].uv = uv
        obj["ec_role"] = "leaf_group"
        obj["age_threshold"] = age_group / 5
        obj.shape_key_add(name="Basis")
        for name, age, height, width in zip(
            AGE_KEY_NAMES, AGES, HEIGHT_RATIOS, WIDTH_RATIOS
        ):
            shape = obj.shape_key_add(name=name)
            for vertex_index, item in enumerate(leaf_meta):
                branch_index = item["branch"]
                root_mature = item["root"]
                if branch_index < 0:
                    center_mature = item["center"]
                    center_age = Vector(
                        (
                            center_mature.x * width,
                            center_mature.y * width,
                            TRUNK_BASE_Z + (center_mature.z - TRUNK_BASE_Z) * height,
                        )
                    )
                    leaf_local = item["original"] - center_mature
                    leaf_scale = 0.42 + 0.58 * math.sqrt(age)
                    shape.data[vertex_index].co = center_age + leaf_local * leaf_scale
                    continue
                root_age = Vector(
                    (
                        root_mature.x * width,
                        root_mature.y * width,
                        TRUNK_BASE_Z + (root_mature.z - TRUNK_BASE_Z) * height,
                    )
                )
                threshold = 0.05 + branch_index * 0.045
                branch_growth = max(
                    0.18,
                    min(1.0, (age - threshold + 0.12) / 0.42),
                )
                crown_width = 0.38 + width * 0.62
                center_mature = item["center"]
                center_local = center_mature - root_mature
                center_age = root_age + Vector(
                    (
                        center_local.x * branch_growth * crown_width,
                        center_local.y * branch_growth * crown_width,
                        center_local.z * branch_growth * height,
                    )
                )
                leaf_local = item["original"] - center_mature
                leaf_scale = 0.52 + 0.48 * math.sqrt(branch_growth)
                shape.data[vertex_index].co = center_age + leaf_local * leaf_scale
            shape.value = 0.0
        objects.append(obj)
    return objects


def create_armature(
    root: bpy.types.Object,
    tree: bpy.types.Object,
    trunk: list[Vector],
    branches: list[list[Vector]],
    metadata: list[dict],
) -> bpy.types.Object:
    armature = bpy.data.armatures.new("MagicTreeRig")
    rig = bpy.data.objects.new("MagicTreeArmature", armature)
    bpy.context.collection.objects.link(rig)
    rig.parent = root
    rig["ec_role"] = "tree_rig"
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    trunk_bones = []
    for index in range(8):
        start = trunk[round(index / 8 * (len(trunk) - 1))]
        end = trunk[round((index + 1) / 8 * (len(trunk) - 1))]
        bone = armature.edit_bones.new(f"Trunk_{index:02d}")
        bone.head = start
        bone.tail = end
        if trunk_bones:
            bone.parent = trunk_bones[-1]
            bone.use_connect = False
        trunk_bones.append(bone)

    for branch_index, path in enumerate(branches):
        bone = armature.edit_bones.new(f"Branch_{branch_index:02d}")
        bone.head = path[0]
        bone.tail = path[-1]
        start_ratio = path[0].z / TREE_HEIGHT
        bone.parent = trunk_bones[min(7, max(0, int(start_ratio * 8)))]

    bpy.ops.object.mode_set(mode="OBJECT")
    modifier = tree.modifiers.new("MagicTreeSkin", "ARMATURE")
    modifier.object = rig
    tree.parent = rig

    for bone in rig.data.bones:
        tree.vertex_groups.new(name=bone.name)
    for vertex_index, item in enumerate(metadata):
        if item["kind"] == "branch":
            group_name = f"Branch_{item['branch']:02d}"
        else:
            group_index = min(7, max(0, int(item["t"] * 8)))
            group_name = f"Trunk_{group_index:02d}"
        tree.vertex_groups[group_name].add([vertex_index], 1.0, "REPLACE")
    return rig


def create_markers(
    root: bpy.types.Object,
    rig: bpy.types.Object,
    trunk: list[Vector],
    branches: list[list[Vector]],
) -> None:
    marker_root = bpy.data.objects.new("MarkerPaths", None)
    bpy.context.collection.objects.link(marker_root)
    marker_root.parent = root
    marker_root["ec_role"] = "marker_paths"

    for index in range(16):
        ratio = index / 15
        point = trunk[round(ratio * (len(trunk) - 1))]
        marker = bpy.data.objects.new(f"TrunkMarker_{index:02d}", None)
        bpy.context.collection.objects.link(marker)
        marker.empty_display_type = "SPHERE"
        marker.empty_display_size = 0.035
        marker.parent = rig
        marker.parent_type = "BONE"
        marker.parent_bone = f"Trunk_{min(7, int(ratio * 8)):02d}"
        marker.matrix_world.translation = point
        marker["marker_path"] = "trunk"
        marker["marker_index"] = index

    for branch_index, path in enumerate(branches):
        for marker_index in range(12):
            ratio = marker_index / 11
            point = path[round(ratio * (len(path) - 1))]
            marker = bpy.data.objects.new(
                f"BranchMarker_{branch_index:02d}_{marker_index:02d}", None
            )
            bpy.context.collection.objects.link(marker)
            marker.empty_display_type = "SPHERE"
            marker.empty_display_size = 0.025
            marker.parent = rig
            marker.parent_type = "BONE"
            marker.parent_bone = f"Branch_{branch_index:02d}"
            marker.matrix_world.translation = point
            marker["marker_path"] = f"branch_{branch_index:02d}"
            marker["marker_index"] = marker_index


def create_shape_animation(tree: bpy.types.Object) -> None:
    keys = tree.data.shape_keys
    keys.animation_data_create()
    action = bpy.data.actions.new("tree_age")
    keys.animation_data.action = action
    frames = (1, 28, 55, 82, 110)
    blocks = [keys.key_blocks[name] for name in AGE_KEY_NAMES]
    for block_index, block in enumerate(blocks):
        for frame_index, frame in enumerate(frames):
            block.value = 1.0 if block_index == frame_index else 0.0
            block.keyframe_insert(data_path="value", frame=frame)
    for curve in action.fcurves:
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
    keys.animation_data.action = None
    track = keys.animation_data.nla_tracks.new()
    track.name = "tree_age"
    track.strips.new("tree_age", 1, action)


def create_rig_actions(rig: bpy.types.Object) -> None:
    rig.animation_data_create()
    definitions = {
        "idle_breath": ((1, 0.0), (60, 0.018), (120, 0.0)),
        "magic_pulse": ((1, 0.0), (18, 0.035), (42, 0.0)),
        "wither": ((1, 0.0), (80, -0.12)),
    }
    for name, frames in definitions.items():
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        branch_bones = [bone for bone in rig.pose.bones if bone.name.startswith("Branch_")]
        for branch_index, pose_bone in enumerate(branch_bones):
            pose_bone.rotation_mode = "XYZ"
            for frame, amplitude in frames:
                pose_bone.rotation_euler.y = amplitude * (1 if branch_index % 2 else -1)
                pose_bone.rotation_euler.z = amplitude * 0.4
                pose_bone.keyframe_insert(
                    data_path="rotation_euler", frame=frame, group=pose_bone.name
                )
        rig.animation_data.action = None
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)


def create_magic_veins(
    root: bpy.types.Object,
    material: bpy.types.Material,
    trunk: list[Vector],
) -> bpy.types.Object:
    curve = bpy.data.curves.new("MagicVeinsCurve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.009
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(31)
    for index, point in enumerate(spline.points):
        t = index / 31
        center = trunk[round(t * (len(trunk) - 1))]
        radius = 0.06 + 0.72 * ((1 - t) ** 0.72)
        angle = t * math.tau * 3.7
        position = center + Vector((math.cos(angle) * radius, math.sin(angle) * radius, 0))
        point.co = (*position, 1)
    obj = bpy.data.objects.new("MagicVeins", curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    obj.parent = root
    obj["ec_role"] = "magic_emissive"
    return obj


def configure_scene(root: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 860
    scene.render.resolution_y = 1864
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.render.image_settings.color_depth = "8"
    scene.render.fps = 60
    scene.frame_start = 1
    scene.frame_end = 120
    scene.world.color = (0.91, 0.87, 0.79)
    scene.view_settings.look = "AgX - Medium High Contrast"

    world_nodes = scene.world.node_tree.nodes if scene.world.use_nodes else None
    if world_nodes is None:
        scene.world.use_nodes = True
        world_nodes = scene.world.node_tree.nodes
    background = world_nodes.get("Background")
    background.inputs["Color"].default_value = (0.982, 0.923, 0.83, 1)
    background.inputs["Strength"].default_value = 0.72

    bpy.ops.object.light_add(type="AREA", location=(-5.5, -6.0, 11.5))
    key = bpy.context.object
    key.name = "WarmKeyLight"
    key.data.energy = 1050
    key.data.shape = "DISK"
    key.data.size = 5.0
    key.data.color = (1.0, 0.73, 0.42)

    bpy.ops.object.light_add(type="AREA", location=(5.0, -2.0, 7.0))
    fill = bpy.context.object
    fill.name = "SoftFillLight"
    fill.data.energy = 560
    fill.data.size = 4.0
    fill.data.color = (0.55, 0.72, 0.44)

    bpy.ops.object.light_add(type="AREA", location=(0, 5.5, 9.0))
    rim = bpy.context.object
    rim.name = "CrownRimLight"
    rim.data.energy = 850
    rim.data.size = 3.0
    rim.data.color = (0.82, 0.94, 0.53)

    bpy.ops.object.camera_add(location=(0.0, -28.5, 6.5))
    camera = bpy.context.object
    camera.name = "StandinCamera"
    camera.data.lens = 58
    camera.data.sensor_width = 36
    target = Vector((0, 0, 4.0))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera

    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.72))
    ground = bpy.context.object
    ground.name = "Ground"
    ground_material = bpy.data.materials.new("GroundMatte")
    ground_material.diffuse_color = (0.982, 0.923, 0.83, 1)
    ground_material.use_nodes = True
    ground_bsdf = ground_material.node_tree.nodes.get("Principled BSDF")
    ground_bsdf.inputs["Base Color"].default_value = (0.982, 0.923, 0.83, 1)
    ground_bsdf.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(ground_material)
    ground["export_exclude"] = True

    root["tree_height_m"] = TREE_HEIGHT
    root["main_branch_count"] = 9
    root["age_shape_keys"] = "age_00,age_25,age_48,age_72,age_100"


def main() -> None:
    clear_scene()
    random.seed(40721)
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)

    root = bpy.data.objects.new("MagicTreeRoot", None)
    bpy.context.collection.objects.link(root)
    root["ec_schema_version"] = 1
    root["ec_role"] = "magic_tree_root"

    bark = material_with_pbr("BarkOldPBR", "bark_old")
    soil_material = material_with_pbr("SoilPBR", "soil")
    leaves = [
        leaf_material("LeafDeep", (0.46, 0.74, 0.24)),
        leaf_material("LeafMid", (0.60, 0.84, 0.30)),
        leaf_material("LeafYoung", (0.76, 0.94, 0.40)),
    ]
    magic = magic_material()

    tree, trunk, branches, secondary, metadata = create_trunk_and_branches(root, bark)
    create_roots(root, bark)
    create_soil(root, soil_material)
    create_leaf_groups(root, trunk, branches, secondary, leaves)
    rig = create_armature(root, tree, trunk, branches, metadata)
    create_markers(root, rig, trunk, branches)
    create_shape_animation(tree)
    create_rig_actions(rig)
    create_magic_veins(root, magic, trunk)

    crown = bpy.data.objects.new("CrownGuide", None)
    bpy.context.collection.objects.link(crown)
    crown.location = (0, 0, 6.4)
    crown.scale = (3.0, 2.4, 1.8)
    crown.parent = root
    crown["ec_role"] = "crown_guide"

    pulse = bpy.data.objects.new("MagicPulse", None)
    bpy.context.collection.objects.link(pulse)
    pulse.location = (0, 0, 3.7)
    pulse.parent = root
    pulse["ec_role"] = "magic_pulse_anchor"

    configure_scene(root)
    bpy.context.scene.frame_set(110)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), compress=True)
    print(f"魔树 Blender 主文件已生成：{BLEND_PATH}")


if __name__ == "__main__":
    main()
