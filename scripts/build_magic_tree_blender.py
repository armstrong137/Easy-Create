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
HEIGHT_RATIOS = (0.24, 0.40, 0.60, 0.80, 1.0)
WIDTH_RATIOS = (0.32, 0.45, 0.62, 0.80, 1.0)
CROWN_RATIOS = (0.34, 0.48, 0.66, 0.83, 1.0)
LEAF_RATIOS = (0.68, 0.76, 0.84, 0.92, 1.0)
ROOT_RATIOS = (0.35, 0.48, 0.64, 0.82, 1.0)
RADIAL_SEGMENTS = 14
TREE_HEIGHT = 8.2
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
    material = bpy.data.materials.new("MagicVeinPBR")
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (0.38, 0.17, 0.025, 1)
    principled.inputs["Emission Color"].default_value = (1.0, 0.46, 0.055, 1)
    principled.inputs["Emission Strength"].default_value = 1.15
    principled.inputs["Roughness"].default_value = 0.48
    return material


def moss_material() -> bpy.types.Material:
    material = bpy.data.materials.new("MossPBR")
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (0.028, 0.065, 0.012, 1)
    principled.inputs["Roughness"].default_value = 0.94
    principled.inputs["Specular IOR Level"].default_value = 0.12
    return material


def cubic_bezier(
    start: Vector,
    control_a: Vector,
    control_b: Vector,
    end: Vector,
    count: int,
) -> list[Vector]:
    points = []
    for index in range(count):
        t = index / (count - 1)
        inv = 1.0 - t
        points.append(
            start * (inv ** 3)
            + control_a * (3.0 * inv * inv * t)
            + control_b * (3.0 * inv * t * t)
            + end * (t ** 3)
        )
    return points


def trunk_path() -> list[Vector]:
    return cubic_bezier(
        Vector((0.0, 0.0, TRUNK_BASE_Z)),
        Vector((-0.22, 0.10, 2.35)),
        Vector((0.34, -0.16, 5.30)),
        Vector((-0.05, 0.08, 6.55)),
        41,
    )


def branch_paths(trunk: list[Vector]) -> list[list[Vector]]:
    # 六根主枝逐根定型，避免等角度、等间距复制形成仙人掌轮廓。
    specs = (
        (0.36, (-0.62, -0.06, 0.22), (-1.92, -0.18, 1.05), (-2.92, 0.10, 2.48)),
        (0.40, (0.66, 0.12, 0.18), (1.98, 0.30, 1.00), (2.98, 0.18, 2.42)),
        (0.47, (-0.56, 0.24, 0.45), (-1.68, 0.44, 1.80), (-2.48, 0.08, 3.24)),
        (0.52, (0.58, -0.18, 0.42), (1.72, -0.34, 1.80), (2.54, 0.05, 3.30)),
        (0.59, (-0.34, 0.26, 0.72), (-1.02, 0.46, 2.18), (-1.52, 0.16, 3.62)),
        (0.64, (0.36, -0.22, 0.70), (1.00, -0.42, 2.18), (1.48, 0.12, 3.54)),
        (0.68, (0.10, 0.18, 0.86), (0.44, 0.26, 2.45), (0.18, 0.08, 3.82)),
    )
    paths = []
    for start_ratio, control_a, control_b, end in specs:
        branch_root = trunk[round(start_ratio * (len(trunk) - 1))].copy()
        paths.append(
            cubic_bezier(
                branch_root,
                branch_root + Vector(control_a),
                branch_root + Vector(control_b),
                branch_root + Vector(end),
                16,
            )
        )
    return paths


def secondary_branch_paths(
    branches: list[list[Vector]],
) -> list[tuple[int, list[Vector]]]:
    secondary = []
    fork_specs = (
        ((5, -1, 1.36, 0.48), (8, 1, 1.26, 0.62), (11, -1, 1.12, 0.76), (13, 1, 0.94, 0.88)),
        ((5, 1, 1.42, 0.46), (8, -1, 1.28, 0.66), (11, 1, 1.10, 0.80), (13, -1, 0.92, 0.90)),
        ((5, 1, 1.30, 0.58), (8, -1, 1.18, 0.72), (11, 1, 1.04, 0.86), (13, -1, 0.88, 0.98)),
        ((5, -1, 1.34, 0.56), (8, 1, 1.20, 0.72), (11, -1, 1.02, 0.86), (13, 1, 0.86, 0.96)),
        ((6, -1, 1.20, 0.66), (10, 1, 1.04, 0.82), (13, -1, 0.88, 0.96)),
        ((6, 1, 1.22, 0.64), (10, -1, 1.06, 0.82), (13, 1, 0.90, 0.96)),
        ((6, -1, 1.16, 0.72), (10, 1, 1.00, 0.88), (13, -1, 0.84, 1.02)),
    )
    for parent_index, parent in enumerate(branches):
        for fork_index, (start_index, sign, length, lift) in enumerate(
            fork_specs[parent_index]
        ):
            root = parent[start_index].copy()
            parent_direction = (parent[min(15, start_index + 1)] - parent[start_index - 1]).normalized()
            side = Vector((-parent_direction.y, parent_direction.x, 0)).normalized()
            direction = (
                parent_direction * (0.46 + 0.06 * fork_index)
                + side * sign * (0.68 - 0.08 * fork_index)
                + Vector((0, 0, lift))
            ).normalized()
            end = root + direction * length
            path = cubic_bezier(
                root,
                root + direction * length * 0.32,
                end + Vector((0, 0, 0.16 + 0.04 * fork_index)),
                end,
                9,
            )
            secondary.append((parent_index, path))
    return secondary


def tertiary_branch_paths(
    secondary: list[tuple[int, list[Vector]]],
) -> list[tuple[int, list[Vector]]]:
    """为每根次级枝补两根细末梢，形成连续树冠而不是枝端叶团。"""
    tertiary = []
    for secondary_index, (parent_index, parent) in enumerate(secondary):
        for fork_index, start_index in enumerate((3, 5, 6)):
            root = parent[start_index].copy()
            tangent = (parent[start_index + 1] - parent[start_index - 1]).normalized()
            side = tangent.cross(Vector((0, 0, 1)))
            if side.length < 0.1:
                side = Vector((1, 0, 0))
            side.normalize()
            sign = -1 if (secondary_index + fork_index) % 2 else 1
            length = 0.62 + 0.09 * ((secondary_index + fork_index) % 4)
            lift = 0.42 + 0.08 * ((secondary_index + 2 * fork_index) % 3)
            direction = (
                tangent * (0.42 + 0.08 * fork_index)
                + side * sign * (0.52 - 0.08 * fork_index)
                + Vector((0, 0, lift))
            ).normalized()
            end = root + direction * length
            path = cubic_bezier(
                root,
                root + direction * length * 0.34,
                end + side * sign * 0.08 + Vector((0, 0, 0.10)),
                end,
                7,
            )
            tertiary.append((parent_index, path))
    return tertiary


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


def branch_growth(age: float, branch_index: int, generation: int) -> float:
    """按主枝层级错峰生长，避免幼苗只是成年树的纵向压缩。"""
    births = (0.0, 0.0, 0.17, 0.17, 0.36, 0.36, 0.0)
    birth = births[branch_index] + max(0, generation - 1) * 0.03
    duration = 0.22 + max(0, generation - 1) * 0.03
    progress = max(0.0, min(1.0, (age - birth) / duration))
    return progress * progress * (3.0 - 2.0 * progress)


def leaf_emergence(age: float, age_group: int) -> float:
    """让新叶在所属枝梢锚点上连续舒展，避免整组叶片突然显隐。"""
    birth = age_group / 5
    progress = max(0.0, min(1.0, (age - birth) / 0.16))
    return progress * progress * (3.0 - 2.0 * progress)


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
    generation: int = 0,
) -> None:
    start_vertex = len(vertices)
    root = (root_override or path[0]).copy()
    for path_index, center in enumerate(path):
        t = path_index / (len(path) - 1)
        normal, binormal = frame_for_path(path, path_index)
        if kind == "trunk":
            amplitude = 0.075 * math.sin(math.pi * t)
        elif kind == "branch":
            amplitude = (
                0.050
                / (1.0 + 0.35 * max(0, generation - 1))
                * math.sin(math.pi * t)
            )
        else:
            amplitude = 0.0
        center = (
            center
            + normal * math.sin(t * math.tau * 2.4 + branch_index * 0.7) * amplitude
            + binormal * math.sin(t * math.tau * 1.7 + branch_index) * amplitude * 0.7
        )
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
                    "generation": generation,
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
    list[tuple[int, list[Vector]]],
    list[dict],
]:
    trunk = trunk_path()
    branches = branch_paths(trunk)
    secondary = secondary_branch_paths(branches)
    tertiary = tertiary_branch_paths(secondary)
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
        lambda t: 0.035
        + 0.76 * ((1 - t) ** 0.70)
        + 0.30 * math.exp(-t * 12),
        "trunk",
    )
    for branch_index, path in enumerate(branches):
        start_radius = (0.40, 0.39, 0.34, 0.33, 0.30, 0.29, 0.27)[branch_index]
        append_tube(
            vertices,
            faces,
            uvs,
            metadata,
            path,
            lambda t, radius=start_radius: 0.014 + radius * ((1 - t) ** 0.88),
            "branch",
            branch_index,
            generation=1,
        )
    for parent_index, path in secondary:
        append_tube(
            vertices,
            faces,
            uvs,
            metadata,
            path,
            lambda t: 0.018 + 0.145 * ((1 - t) ** 0.96),
            "branch",
            parent_index,
            branches[parent_index][0],
            generation=2,
        )
    for parent_index, path in tertiary:
        append_tube(
            vertices,
            faces,
            uvs,
            metadata,
            path,
            lambda t: 0.006 + 0.052 * ((1 - t) ** 1.08),
            "branch",
            parent_index,
            branches[parent_index][0],
            generation=3,
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
    for age_index, (name, age, height, width, crown) in enumerate(
        zip(AGE_KEY_NAMES, AGES, HEIGHT_RATIOS, WIDTH_RATIOS, CROWN_RATIOS)
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
                local = original - root_mature
                growth = branch_growth(
                    age,
                    branch_index,
                    item["generation"],
                )
                shaped = root_age + Vector(
                    (
                        local.x * crown * growth,
                        local.y * crown * growth,
                        local.z * (0.38 + 0.62 * height) * growth,
                    )
                )
            shape.data[vertex_index].co = shaped
        shape.value = 0.0
    twig_guide = bpy.data.objects.new("TertiaryTwigs", None)
    bpy.context.collection.objects.link(twig_guide)
    twig_guide.parent = tree
    twig_guide["ec_role"] = "tertiary_twig_layer"
    twig_guide["twig_count"] = len(tertiary)
    return tree, trunk, branches, secondary, tertiary, metadata


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
    root_specs = (
        (-2.92, 2.70, 0.30),
        (-2.62, 2.34, 0.28),
        (-2.28, 2.58, 0.35),
        (-1.92, 2.18, 0.27),
        (-1.54, 2.82, 0.34),
        (-1.10, 2.20, 0.25),
        (-0.62, 2.72, 0.31),
        (-0.16, 2.22, 0.24),
        (0.34, 2.74, 0.32),
        (0.82, 2.16, 0.26),
        (1.30, 2.66, 0.34),
        (1.78, 2.28, 0.27),
        (2.22, 2.60, 0.31),
        (2.70, 2.32, 0.27),
    )
    for index, (angle, length, start_radius) in enumerate(root_specs):
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        side = Vector((-direction.y, direction.x, 0))
        start = direction * 0.12 + Vector((0, 0, 0.72 - 0.04 * (index % 3)))
        path = cubic_bezier(
            start,
            start + direction * 0.62 + side * (0.10 if index % 2 else -0.08),
            direction * (length * 0.78) + side * (0.16 if index % 3 else -0.14) + Vector((0, 0, 0.04)),
            direction * length + Vector((0, 0, -0.10)),
            12,
        )
        append_tube(
            vertices,
            faces,
            uvs,
            metadata,
            path,
            lambda t, radius=start_radius: 0.025
            + radius * ((1 - t) ** 1.24),
            "root",
            index,
        )
    roots = create_mesh_object("Roots", vertices, faces, bark, root)
    uv_layer = roots.data.uv_layers.new(name="UVMap")
    for loop in roots.data.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    roots["ec_role"] = "roots"
    roots["root_style"] = "eight_irregular_grounding_roots"
    roots.shape_key_add(name="Basis")
    for name, age, width, span in zip(
        AGE_KEY_NAMES, AGES, WIDTH_RATIOS, ROOT_RATIOS
    ):
        shape = roots.shape_key_add(name=name)
        for vertex_index, vertex in enumerate(roots.data.vertices):
            original = vertex.co
            shape.data[vertex_index].co = Vector(
                (
                    original.x * span,
                    original.y * span,
                    original.z * (0.42 + width * 0.58),
                )
            )
        shape.value = 0.0
    for name, role in (
        ("RootFlare", "root_flare"),
        ("ExposedRoots", "exposed_roots"),
    ):
        marker = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(marker)
        marker.parent = roots
        marker["ec_role"] = role
    return roots


def create_soil(root: bpy.types.Object, material: bpy.types.Material) -> bpy.types.Object:
    random.seed(60211)
    soil = bpy.data.objects.new("Soil", None)
    bpy.context.collection.objects.link(soil)
    soil.parent = root
    soil["ec_role"] = "ground_contact_anchor"

    debris_vertices = []
    debris_faces = []
    for pebble in range(118):
        angle = random.uniform(0, math.tau)
        radius = random.uniform(0.42, 2.74)
        center = Vector(
            (
                math.cos(angle) * radius,
                math.sin(angle) * radius * 0.70,
                random.uniform(-0.11, 0.02),
            )
        )
        size = random.uniform(0.035, 0.105)
        start = len(debris_vertices)
        debris_vertices.extend(
            tuple(center + Vector(offset) * size)
            for offset in (
                (-1.0, -0.7, 0.0),
                (0.9, -0.6, 0.0),
                (0.8, 0.8, 0.0),
                (-0.8, 0.7, 0.0),
                (0.0, 0.0, 0.75),
            )
        )
        debris_faces.extend(
            (
                (start, start + 1, start + 4),
                (start + 1, start + 2, start + 4),
                (start + 2, start + 3, start + 4),
                (start + 3, start, start + 4),
                (start + 3, start + 2, start + 1, start),
            )
        )
    debris = create_mesh_object(
        "GroundDebris", debris_vertices, debris_faces, material, root
    )
    uv_layer = debris.data.uv_layers.new(name="UVMap")
    for loop in debris.data.loops:
        vertex = debris.data.vertices[loop.vertex_index].co
        uv_layer.data[loop.index].uv = (
            (vertex.x + 3.0) / 6.0,
            (vertex.y + 2.1) / 4.2,
        )
    debris["ec_role"] = "ground_debris"
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
    generation: int,
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
            "generation": generation,
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
    tertiary: list[tuple[int, list[Vector]]],
    materials: list[bpy.types.Material],
) -> tuple[list[bpy.types.Object], int]:
    random.seed(40721)
    groups = [([], [], []) for _ in range(6)]
    cluster_specs: list[tuple[int, list[Vector], int, int, float]] = []
    for branch_index, path in enumerate(branches):
        cluster_specs.extend(
            (
                (branch_index, path, 1, 0, 0.46),
                (branch_index, path, 1, 0, 0.54),
                (branch_index, path, 1, 0, 0.70),
                (branch_index, path, 1, 0, 0.86),
                (branch_index, path, 1, 0, 1.00),
            )
        )
    for secondary_index, (branch_index, path) in enumerate(secondary):
        age_group = secondary_index % 6
        cluster_specs.extend(
            (
                (branch_index, path, 2, age_group, 0.52),
                (branch_index, path, 2, age_group, 0.72),
                (branch_index, path, 2, age_group, 1.00),
            )
        )
    for tertiary_index, (branch_index, path) in enumerate(tertiary):
        age_group = tertiary_index % 6
        cluster_specs.extend(
            (
                (branch_index, path, 3, age_group, 0.34),
                (branch_index, path, 3, age_group, 0.48),
                (branch_index, path, 3, age_group, 0.74),
                (branch_index, path, 3, age_group, 1.00),
            )
        )

    # 早期也有完整树冠，高阶段只在自然枝梢间增加新叶簇。
    cluster_specs.extend(
        (
            (-1, trunk, 0, 0, 0.74),
            (-1, trunk, 0, 0, 0.86),
            (-1, trunk, 0, 0, 0.96),
            (-1, trunk, 0, 0, 1.00),
        )
    )
    for cluster_index, (branch_index, path, generation, age_group, ratio) in enumerate(
        cluster_specs
    ):
        path_index = max(1, round((len(path) - 1) * ratio))
        centerline = path[path_index]
        tangent = (path[path_index] - path[path_index - 1]).normalized()
        count = 8 + cluster_index % 4
        vertices, faces, leaf_meta = groups[age_group]
        for leaf_index in range(count):
            angle = math.tau * leaf_index / count + random.uniform(-0.34, 0.34)
            radial = Vector(
                (
                    math.cos(angle),
                    math.sin(angle) * random.uniform(0.58, 0.88),
                    random.uniform(-0.04, 0.44),
                )
            ).normalized()
            direction = (radial * 0.82 + tangent * 0.18).normalized()
            center = centerline + direction * random.uniform(0.13, 0.30)
            append_leaf(
                vertices,
                faces,
                leaf_meta,
                center,
                direction,
                random.uniform(0.110, 0.155),
                random.uniform(0.30, 0.43),
                path[0],
                branch_index,
                generation,
            )

    leaf_root = bpy.data.objects.new("LeafClusters", None)
    bpy.context.collection.objects.link(leaf_root)
    leaf_root.parent = root
    leaf_root["ec_role"] = "broadleaf_clusters"

    objects = []
    for age_group, (vertices, faces, leaf_meta) in enumerate(groups):
        obj = create_mesh_object(
            f"LeavesAge{age_group}", vertices, faces, materials[0], root
        )
        obj.parent = leaf_root
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
        for name, age, height, width, crown, leaf_scale in zip(
            AGE_KEY_NAMES,
            AGES,
            HEIGHT_RATIOS,
            WIDTH_RATIOS,
            CROWN_RATIOS,
            LEAF_RATIOS,
        ):
            shape = obj.shape_key_add(name=name)
            emergence = leaf_emergence(age, age_group)
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
                    shape.data[vertex_index].co = (
                        center_age + leaf_local * leaf_scale * emergence
                    )
                    continue
                root_age = Vector(
                    (
                        root_mature.x * width,
                        root_mature.y * width,
                        TRUNK_BASE_Z + (root_mature.z - TRUNK_BASE_Z) * height,
                    )
                )
                center_mature = item["center"]
                center_local = center_mature - root_mature
                growth = branch_growth(
                    age,
                    branch_index,
                    item["generation"],
                )
                center_age = root_age + Vector(
                    (
                        center_local.x * crown * growth,
                        center_local.y * crown * growth,
                        center_local.z * (0.38 + 0.62 * height) * growth,
                    )
                )
                leaf_local = item["original"] - center_mature
                shape.data[vertex_index].co = (
                    center_age + leaf_local * leaf_scale * growth * emergence
                )
            shape.value = 0.0
        objects.append(obj)
    return objects, sum(len(faces) for _, faces, _ in groups)


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


def create_moss_patches(
    root: bpy.types.Object,
    material: bpy.types.Material,
) -> bpy.types.Object:
    # 苔藓只保留在不会因形态键变形而漂浮的根颈区域。
    center = Vector((0.0, -0.24, 0.34))
    vertices = [tuple(center)]
    faces = []
    for point_index in range(10):
        angle = math.tau * point_index / 10
        vertices.append(
            tuple(
                center
                + Vector(
                    (
                        math.cos(angle) * 0.055,
                        -0.004,
                        math.sin(angle) * 0.040,
                    )
                )
            )
        )
    for point_index in range(10):
        faces.append(
            (
                0,
                1 + point_index,
                1 + (point_index + 1) % 10,
            )
        )
    moss = create_mesh_object("MossPatches", vertices, faces, material, root)
    moss["ec_role"] = "moss_patches"
    return moss


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
    root["main_branch_count"] = 7
    root["age_shape_keys"] = "age_00,age_25,age_48,age_72,age_100"
    root["formal_asset"] = True
    root["art_style"] = "ancient_broadleaf_v2"
    root["topology_strategy"] = "art_directed_explicit_branches"
    root["leaf_emergence_mode"] = "morph_scale_at_anchor"


def main() -> None:
    clear_scene()
    random.seed(40721)
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)

    root = bpy.data.objects.new("MagicTreeRoot", None)
    bpy.context.collection.objects.link(root)
    root["ec_schema_version"] = 1
    root["ec_role"] = "magic_tree_root"

    bark = material_with_pbr("BarkOldPBR", "bark_old")
    soil_material = material_with_pbr("GroundPBR", "soil")
    leaves = [
        leaf_material("LeafBroadPBR", (0.34, 0.60, 0.16)),
        leaf_material("LeafBroadSunlit", (0.52, 0.74, 0.22)),
        leaf_material("LeafBroadYoung", (0.68, 0.84, 0.28)),
    ]
    magic = magic_material()
    moss = moss_material()

    tree, trunk, branches, secondary, tertiary, metadata = create_trunk_and_branches(
        root, bark
    )
    create_roots(root, bark)
    create_soil(root, soil_material)
    _, leaf_card_count = create_leaf_groups(
        root, trunk, branches, secondary, tertiary, leaves
    )
    root["tertiary_twig_count"] = len(tertiary)
    root["leaf_card_count"] = leaf_card_count
    rig = create_armature(root, tree, trunk, branches, metadata)
    create_markers(root, rig, trunk, branches)
    create_shape_animation(tree)
    create_rig_actions(rig)
    create_magic_veins(root, magic, trunk)
    create_moss_patches(root, moss)

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
