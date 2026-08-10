from __future__ import annotations

import os
import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "build" / "magic_tree" / "magic_tree.raw.glb"
TEMP = ROOT / "build" / "magic_tree" / "external"
FINAL_ROOT = ROOT / "assets" / "3d" / "magic_tree"
FINAL = FINAL_ROOT / "magic_tree.glb"
TEXTURES = FINAL_ROOT / "textures"
DEFAULT_GLTFPACK = Path(os.environ.get("LOCALAPPDATA", "")) / (
    "CodexTools/gltfpack/1.2/gltfpack.exe"
)


def _find_gltfpack() -> Path:
    explicit = os.environ.get("GLTFPACK")
    candidates = [Path(explicit)] if explicit else []
    candidates.extend([DEFAULT_GLTFPACK, Path("gltfpack.exe")])
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
        resolved = shutil.which(str(candidate))
        if resolved:
            return Path(resolved)
    raise FileNotFoundError(
        "未找到 gltfpack；请设置 GLTFPACK，或安装到用户工具缓存 CodexTools/gltfpack/1.2"
    )


def _run(output: Path) -> None:
    command = [
        str(_find_gltfpack()),
        "-i",
        str(RAW),
        "-o",
        str(output),
        "-c",
        "-tc",
        "color,attrib",
        "-tu",
        "normal",
        "-tq",
        "9",
        "-tl",
        "1024",
        "-kn",
        "-km",
        "-ke",
    ]
    subprocess.run(command, check=True)


def main() -> None:
    if not RAW.is_file():
        raise FileNotFoundError(f"缺少 Blender 原始导出：{RAW}")
    TEMP.mkdir(parents=True, exist_ok=True)
    FINAL_ROOT.mkdir(parents=True, exist_ok=True)
    TEXTURES.mkdir(parents=True, exist_ok=True)

    external = TEMP / "magic_tree.gltf"
    _run(external)
    _run(FINAL)

    for old in TEXTURES.glob("*.ktx2"):
        old.unlink()
    manifest = json.loads(external.read_text(encoding="utf-8"))
    buffer_uri = manifest["buffers"][0]["uri"]
    buffer_data = (TEMP / buffer_uri).read_bytes()
    generated = []
    for image_index, image in enumerate(manifest.get("images", [])):
        if image.get("mimeType") != "image/ktx2":
            continue
        view = manifest["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        end = start + view["byteLength"]
        output = TEXTURES / f"texture_{image_index:02d}.ktx2"
        output.write_bytes(buffer_data[start:end])
        generated.append(output)
    if not generated:
        raise RuntimeError("压缩清单中没有 KTX2 bufferView")
    print(f"最终魔树 GLB：{FINAL} ({FINAL.stat().st_size} bytes)")
    print(f"KTX2 纹理：{len(generated)} 张")


if __name__ == "__main__":
    main()
