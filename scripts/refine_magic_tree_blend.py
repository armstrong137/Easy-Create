from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


OLD_TOP_SPREAD = 1.16
OLD_BASE_FLARE = 1.84
TARGET_TOP_SPREAD = 1.34
TARGET_BASE_FLARE = 2.45
TARGET_LEAF_ANCHORS = 2600
REFINEMENT_VERSION = 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="细化正式实时 3D 古树母版")
    parser.add_argument("--output-blend", type=Path, required=True)
    parser.add_argument("--output-glb", type=Path)
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(arguments)


def flare(normalized: float, top: float, base: float) -> float:
    return top + (base - top) * (1.0 - normalized) ** 3.2


def widen_tree_shapes(tree: bpy.types.Object) -> None:
    blocks = tree.data.shape_keys.key_blocks
    basis = blocks["Basis"]
    min_z = min(point.co.z for point in basis.data)
    max_z = max(point.co.z for point in basis.data)
    span = max(max_z - min_z, 0.001)
    ratios = []
    for point in basis.data:
        normalized = max(0.0, min(1.0, (point.co.z - min_z) / span))
        old = flare(normalized, OLD_TOP_SPREAD, OLD_BASE_FLARE)
        target = flare(normalized, TARGET_TOP_SPREAD, TARGET_BASE_FLARE)
        ratios.append(target / old)
    for block in blocks:
        for index, point in enumerate(block.data):
            point.co.x *= ratios[index]
            point.co.y *= ratios[index]


def rebuild_crown_guide(guide: bpy.types.Object) -> None:
    old_mesh = guide.data
    anchor_count = int(guide.get("anchor_count", len(old_mesh.vertices) // 3))
    centers = [old_mesh.vertices[index * 3].co.copy() for index in range(anchor_count)]
    birth_attribute = old_mesh.attributes.get("_BIRTH")
    births = [
        float(birth_attribute.data[index * 3].value) if birth_attribute else 0.0
        for index in range(anchor_count)
    ]
    min_z = min(point.z for point in centers)
    max_z = max(point.z for point in centers)
    span = max(max_z - min_z, 0.001)
    for point in centers:
        normalized = max(0.0, min(1.0, (point.z - min_z) / span))
        spread = flare(normalized, TARGET_TOP_SPREAD, TARGET_BASE_FLARE)
        point.x *= spread
        point.y *= spread

    base_count = len(centers)
    for index in range(max(0, TARGET_LEAF_ANCHORS - base_count)):
        source_index = (index * 619 + 97) % base_count
        source = centers[source_index]
        angle = index * 2.399963229728653
        radius = 0.018 + (index % 7) * 0.004
        centers.append(
            source
            + Vector(
                (
                    math.cos(angle) * radius,
                    math.sin(angle) * radius,
                    ((index % 5) - 2) * 0.006,
                )
            )
        )
        births.append(births[source_index])

    vertices = []
    faces = []
    for point in centers:
        start = len(vertices)
        vertices.extend(
            (
                point,
                point + Vector((0.0001, 0, 0)),
                point + Vector((0, 0.0001, 0)),
            )
        )
        faces.append((start, start + 1, start + 2))
    mesh = bpy.data.meshes.new("CrownGuideMeshRefined")
    mesh.from_pydata(vertices, [], faces)
    birth = mesh.attributes.new("_BIRTH", "FLOAT", "POINT")
    for index, item in enumerate(birth.data):
        item.value = births[index // 3] if index % 3 == 0 else 2.0
    guide.data = mesh
    guide["anchor_count"] = len(centers)
    bpy.data.meshes.remove(old_mesh)


def ensure_bark_tint(tree: bpy.types.Object) -> None:
    for material in tree.data.materials:
        if not material:
            continue
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        if any(
            node.type == "MIX_RGB" and node.blend_type == "MULTIPLY"
            for node in nodes
        ):
            continue
        bsdf = nodes.get("Principled BSDF")
        if not bsdf:
            continue
        base = bsdf.inputs["Base Color"]
        if base.is_linked:
            source = base.links[0].from_socket
            tint = nodes.new("ShaderNodeMixRGB")
            tint.name = "EasyCreateAncientBarkTint"
            tint.blend_type = "MULTIPLY"
            tint.inputs[0].default_value = 0.93
            tint.inputs[2].default_value = (0.10, 0.038, 0.012, 1)
            links.remove(base.links[0])
            links.new(source, tint.inputs[1])
            links.new(tint.outputs[0], base)
        bsdf.inputs["Roughness"].default_value = 0.88


def add_root_age_shapes(roots: bpy.types.Object) -> None:
    coordinates = [vertex.co.copy() for vertex in roots.data.vertices]
    min_z = min(point.z for point in coordinates)
    max_z = max(point.z for point in coordinates)
    span = max(max_z - min_z, 0.001)
    roots.shape_key_add(name="Basis")
    for name, height, radial in zip(
        ("age_00", "age_25", "age_48", "age_72", "age_100"),
        (0.20, 0.38, 0.59, 0.80, 1.0),
        (0.06, 0.19, 0.43, 0.72, 1.0),
    ):
        shape = roots.shape_key_add(name=name)
        for index, point in enumerate(coordinates):
            normalized = max(0.0, min(1.0, (point.z - min_z) / span))
            relief = 0.76 + normalized * 0.24
            shape.data[index].co = (
                point.x * radial * relief,
                point.y * radial * relief,
                min_z + (point.z - min_z) * height,
            )
        shape.value = 0.0


def append_root_tube(
    vertices: list[Vector],
    faces: list[tuple[int, ...]],
    uvs: list[tuple[float, float]],
    path: list[Vector],
    widths: list[float],
    ring_segments: int = 14,
    texture_offset: float = 0.0,
) -> None:
    start = len(vertices)
    for step, center in enumerate(path):
        tangent = (
            path[min(step + 1, len(path) - 1)]
            - path[max(0, step - 1)]
        ).normalized()
        side = tangent.cross(Vector((0, 0, 1)))
        if side.length < 0.001:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(tangent).normalized()
        progress = step / max(1, len(path) - 1)
        width = widths[step]
        thickness = width * (0.46 - progress * 0.22)
        for ring_index in range(ring_segments):
            angle = math.tau * ring_index / ring_segments
            ridge = 1.0 + 0.07 * math.sin(ring_index * 3.0 + step * 0.83)
            vertices.append(
                center
                + side * math.cos(angle) * width * ridge
                + up * math.sin(angle) * thickness
            )
            uvs.append((ring_index / ring_segments, progress * 3.6 + texture_offset))
    for step in range(len(path) - 1):
        ring = start + step * ring_segments
        next_ring = ring + ring_segments
        for ring_index in range(ring_segments):
            following = (ring_index + 1) % ring_segments
            faces.append(
                (
                    ring + ring_index,
                    ring + following,
                    next_ring + following,
                    next_ring + ring_index,
                )
            )
    faces.append(tuple(start + index for index in reversed(range(ring_segments))))
    end = start + (len(path) - 1) * ring_segments
    faces.append(tuple(end + index for index in range(ring_segments)))


def rebuild_organic_roots(roots: bpy.types.Object, tree: bpy.types.Object) -> None:
    root_count = 7
    root_specs = (
        (-3.00, 1.92, 0.30, 0.13, -0.16),
        (-2.65, 2.28, 0.42, 0.17, 0.20),
        (-2.25, 1.98, 0.34, 0.14, -0.11),
        (-0.85, 2.22, 0.45, 0.18, 0.15),
        (-0.45, 1.88, 0.32, 0.14, -0.20),
        (0.10, 2.08, 0.40, 0.16, 0.13),
        (2.55, 1.80, 0.30, 0.13, -0.14),
    )
    vertices: list[Vector] = []
    faces: list[tuple[int, ...]] = []
    uvs: list[tuple[float, float]] = []
    buttress_rings = (
        (0.38, 0.66),
        (0.50, 0.43),
        (0.68, 0.20),
        (0.86, 0.035),
    )
    buttress_segments = 28
    for ring_index, (radius, z) in enumerate(buttress_rings):
        for segment in range(buttress_segments):
            angle = math.tau * segment / buttress_segments
            irregularity = 1.0 + 0.07 * math.sin(segment * 2.1 + ring_index * 0.8)
            vertices.append(
                Vector(
                    (
                        math.cos(angle) * radius * irregularity,
                        math.sin(angle) * radius * 0.74 * irregularity,
                        z + 0.018 * math.sin(segment * 1.7),
                    )
                )
            )
            uvs.append((segment / buttress_segments, ring_index * 0.62))
    for ring_index in range(len(buttress_rings) - 1):
        ring = ring_index * buttress_segments
        next_ring = ring + buttress_segments
        for segment in range(buttress_segments):
            following = (segment + 1) % buttress_segments
            faces.append(
                (
                    ring + segment,
                    ring + following,
                    next_ring + following,
                    next_ring + segment,
                )
            )
    major_paths: list[tuple[list[Vector], float]] = []
    for root_index, (angle, reach, start_z, base_width, bend) in enumerate(root_specs):
        path = []
        widths = []
        for step in range(19):
            progress = step / 18
            direction = angle + bend * math.sin(progress * math.pi)
            distance = 0.15 + (reach - 0.15) * progress**0.78
            path.append(
                Vector(
                    (
                        math.cos(direction) * distance,
                        math.sin(direction) * distance,
                        0.025
                        + start_z * (1.0 - progress) ** 1.52
                        + 0.025 * math.sin(progress * math.pi),
                    )
                )
            )
            irregularity = 1.0 + 0.08 * math.sin(root_index * 1.7 + step * 1.13)
            widths.append((base_width * (1.0 - progress) ** 0.78 + 0.022) * irregularity)
        append_root_tube(
            vertices,
            faces,
            uvs,
            path,
            widths,
            texture_offset=root_index * 0.37,
        )
        major_paths.append((path, angle))

    for root_index, (path, angle) in enumerate(major_paths):
        if root_index % 2 == 0:
            continue
        start_step = 10 + root_index % 3
        origin = path[start_step]
        direction = angle + (-0.42 if root_index % 4 == 1 else 0.38)
        rootlet_path = []
        rootlet_widths = []
        for step in range(9):
            progress = step / 8
            reach = 0.74 + (root_index % 3) * 0.13
            rootlet_path.append(
                origin
                + Vector(
                    (
                        math.cos(direction) * reach * progress,
                        math.sin(direction) * reach * progress,
                        (0.018 - origin.z) * progress,
                    )
                )
            )
            rootlet_widths.append(0.082 * (1.0 - progress) ** 0.82 + 0.010)
        append_root_tube(
            vertices,
            faces,
            uvs,
            rootlet_path,
            rootlet_widths,
            ring_segments=10,
            texture_offset=root_index * 0.29,
        )

    old_mesh = roots.data
    material = next(
        (
            item
            for item in tree.data.materials
            if item and item.name.startswith("BarkOldPBR")
        ),
        tree.data.materials[0] if tree.data.materials else None,
    )
    mesh = bpy.data.meshes.new("OrganicAncientRootsMesh")
    mesh.from_pydata(vertices, [], faces)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    if material:
        mesh.materials.append(material)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    roots.data = mesh
    roots["root_count"] = root_count
    roots["root_style"] = "asymmetric_buttress_with_rootlets"
    roots.hide_render = False
    add_root_age_shapes(roots)
    bpy.data.meshes.remove(old_mesh)


def hide_flat_ground_artifact(tree: bpy.types.Object) -> int:
    material_name = "GroundArtifactTransparent"
    material = bpy.data.materials.get(material_name) or bpy.data.materials.new(material_name)
    material.use_nodes = True
    material.diffuse_color = (1.0, 1.0, 1.0, 0.0)
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        bsdf.inputs["Alpha"].default_value = 0.0

    material_index = tree.data.materials.find(material_name)
    if material_index < 0:
        tree.data.materials.append(material)
        material_index = len(tree.data.materials) - 1

    hidden_faces = 0
    for polygon in tree.data.polygons:
        if (
            polygon.center.z < 0.08
            and polygon.normal.z > 0.65
            and math.hypot(polygon.center.x, polygon.center.y) > 0.20
        ):
            polygon.material_index = material_index
            hidden_faces += 1
    tree["ground_artifact_faces_hidden"] = hidden_faces
    return hidden_faces


def main() -> None:
    args = parse_args()
    root = bpy.data.objects["MagicTreeRoot"]
    tree = bpy.data.objects["TrunkSkinned"]
    if int(root.get("refinement_version", 0)) < REFINEMENT_VERSION:
        widen_tree_shapes(tree)
        rebuild_crown_guide(bpy.data.objects["CrownGuide"])
        root["leaf_card_count"] = TARGET_LEAF_ANCHORS
        root["refinement_version"] = REFINEMENT_VERSION
    ensure_bark_tint(tree)
    rebuild_organic_roots(bpy.data.objects["Roots"], tree)
    hidden_faces = hide_flat_ground_artifact(tree)
    args.output_blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output_blend.resolve()))
    if args.output_glb:
        args.output_glb.parent.mkdir(parents=True, exist_ok=True)
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
        f"MAGIC_TREE_REFINED=version:{REFINEMENT_VERSION},"
        f"leafAnchors:{TARGET_LEAF_ANCHORS},hiddenGroundFaces:{hidden_faces}"
    )


if __name__ == "__main__":
    main()
