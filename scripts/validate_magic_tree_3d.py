from __future__ import annotations

import argparse
import json
import struct
import subprocess
import sys
from pathlib import Path


REQUIRED_NODES = {
    "MagicTreeRoot",
    "Soil",
    "Roots",
    "TrunkSkinned",
    "MagicTreeArmature",
    "CrownGuide",
}
REQUIRED_ANIMATIONS = {"tree_age", "idle_breath", "magic_pulse", "wither"}
REQUIRED_TARGETS = {"age_00", "age_25", "age_48", "age_72", "age_100"}
REQUIRED_EXTENSIONS = {"EXT_meshopt_compression", "KHR_texture_basisu"}
KTX2_MAGIC = b"\xabKTX 20\xbb\r\n\x1a\n"
MAX_PACKAGE_BYTES = 25 * 1024 * 1024


def parse_glb(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("不是有效 GLB 文件")
    version, total_length = struct.unpack_from("<II", data, 4)
    if version != 2 or total_length != len(data):
        raise ValueError("GLB 版本或声明长度错误")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError("GLB 首块不是 JSON")
    payload = data[20 : 20 + chunk_length].rstrip(b" \0")
    return json.loads(payload.decode("utf-8"))


def validate_khronos(root: Path, glb: Path) -> dict:
    script = root / "tools" / "tree_scene" / "scripts" / "validate-gltf.mjs"
    result = subprocess.run(
        ["node", str(script), str(glb)],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if not result.stdout:
        raise RuntimeError(result.stderr.strip() or "Khronos validator 无输出")
    report = json.loads(result.stdout)
    report["processExitCode"] = result.returncode
    return report


def validate(root: Path, glb: Path) -> dict:
    errors: list[str] = []
    manifest = parse_glb(glb)
    names = {node.get("name", "") for node in manifest.get("nodes", [])}
    missing_nodes = sorted(REQUIRED_NODES - names)
    if missing_nodes:
        errors.append(f"缺少节点：{', '.join(missing_nodes)}")

    animations = {item.get("name", "") for item in manifest.get("animations", [])}
    missing_animations = sorted(REQUIRED_ANIMATIONS - animations)
    if missing_animations:
        errors.append(f"缺少动画：{', '.join(missing_animations)}")
    if not manifest.get("skins"):
        errors.append("缺少 skin")

    trunk_markers = sum(name.startswith("TrunkMarker_") for name in names)
    branch_markers = sum(name.startswith("BranchMarker_") for name in names)
    if trunk_markers < 16:
        errors.append(f"主干 marker 不足：{trunk_markers}/16")
    if branch_markers < 84:
        errors.append(f"主枝 marker 不足：{branch_markers}/84")

    nodes = manifest.get("nodes", [])
    trunk_node_index = next(
        (index for index, node in enumerate(nodes) if node.get("name") == "TrunkSkinned"),
        None,
    )
    trunk_mesh = None
    pending = [trunk_node_index] if trunk_node_index is not None else []
    while pending:
        node = nodes[pending.pop()]
        if node.get("mesh") is not None:
            trunk_mesh = manifest.get("meshes", [])[node["mesh"]]
            break
        pending.extend(node.get("children", []))
    target_names = set((trunk_mesh or {}).get("extras", {}).get("targetNames", []))
    missing_targets = sorted(REQUIRED_TARGETS - target_names)
    if missing_targets:
        errors.append(f"缺少树龄形态键：{', '.join(missing_targets)}")

    extensions = set(manifest.get("extensionsUsed", []))
    missing_extensions = sorted(REQUIRED_EXTENSIONS - extensions)
    if missing_extensions:
        errors.append(f"缺少压缩扩展：{', '.join(missing_extensions)}")

    texture_dir = glb.parent / "textures"
    textures = sorted(texture_dir.glob("*.ktx2"))
    if not textures:
        errors.append("缺少独立 KTX2 纹理")
    for texture in textures:
        if texture.read_bytes()[:12] != KTX2_MAGIC:
            errors.append(f"KTX2 文件头错误：{texture.name}")

    package_bytes = glb.stat().st_size + sum(texture.stat().st_size for texture in textures)
    if package_bytes > MAX_PACKAGE_BYTES:
        errors.append(
            f"GLB + KTX2 超过 25MiB：{package_bytes / 1024 / 1024:.2f}MiB"
        )

    khronos = validate_khronos(root, glb)
    issues = khronos.get("issues", {})
    if issues.get("numErrors", 0) > 0:
        errors.append(f"Khronos Validator 有 {issues['numErrors']} 个 error")

    triangle_count = 0
    accessors = manifest.get("accessors", [])
    for mesh in manifest.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            accessor_index = primitive.get("indices")
            if accessor_index is not None:
                triangle_count += accessors[accessor_index].get("count", 0) // 3

    return {
        "pass": not errors,
        "glb": str(glb),
        "glbBytes": glb.stat().st_size,
        "packageBytes": package_bytes,
        "nodeCount": len(manifest.get("nodes", [])),
        "meshCount": len(manifest.get("meshes", [])),
        "skinCount": len(manifest.get("skins", [])),
        "triangleCount": triangle_count,
        "animations": sorted(animations),
        "trunkMarkers": trunk_markers,
        "branchMarkers": branch_markers,
        "morphTargets": sorted(target_names),
        "extensionsUsed": sorted(extensions),
        "ktx2Count": len(textures),
        "khronosErrors": issues.get("numErrors", 0),
        "khronosWarnings": issues.get("numWarnings", 0),
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="验证实时 3D 魔树 GLB 契约")
    parser.add_argument("glb", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    report = validate(args.root.resolve(), args.glb.resolve())
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
