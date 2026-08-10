from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, UnidentifiedImageError


REFERENCE_SIZES = {
    "树形正视图.png": (1024, 1400),
    "树形侧视图.png": (1024, 1400),
    "建模母版-成熟树四视图.png": (1600, 900),
    "五阶段成长分镜.png": (1600, 900),
    "建模母版-五阶段侧视图.png": (1600, 900),
    "章节枝六阶段分镜.png": (1600, 900),
    "材质母版-PBR细节.png": (1500, 900),
    "左右分区交互效果图.png": (900, 1400),
    "树龄与浏览解耦对照图.png": (1600, 900),
    "章节目枝直接承托效果图.png": (900, 1400),
}

TEXTURE_SIZES = {
    "bark_old_basecolor_source.png": (1024, 1024),
    "soil_basecolor_source.png": (1024, 1024),
    "leaf_atlas_rgba.png": (1024, 768),
}

REQUIRED_DOCUMENTS = (
    "README.md",
    "licenses/ASSET_LICENSES.md",
)


def add_error(
    errors: list[dict[str, Any]], code: str, path: Path, message: str
) -> None:
    errors.append({"code": code, "path": path.as_posix(), "message": message})


def inspect_image(
    path: Path,
    minimum_size: tuple[int, int],
    errors: list[dict[str, Any]],
) -> dict[str, Any] | None:
    if not path.is_file():
        add_error(errors, "missing_file", path, "缺少必需文件")
        return None

    try:
        with Image.open(path) as image:
            image.load()
            width, height = image.size
            mode = image.mode
    except (OSError, UnidentifiedImageError) as error:
        add_error(errors, "decode_error", path, f"图片无法解码：{error}")
        return None

    min_width, min_height = minimum_size
    if width < min_width or height < min_height:
        add_error(
            errors,
            "min_size",
            path,
            f"分辨率 {width}x{height}，最低要求 {min_width}x{min_height}",
        )

    return {
        "path": path.as_posix(),
        "size": [width, height],
        "mode": mode,
        "bytes": path.stat().st_size,
    }


def inspect_leaf_alpha(
    path: Path, errors: list[dict[str, Any]]
) -> dict[str, float] | None:
    if not path.is_file():
        return None

    try:
        with Image.open(path) as image:
            if image.mode != "RGBA":
                add_error(errors, "leaf_mode", path, "叶片图集必须为 RGBA")
                return None
            alpha = image.getchannel("A")
            histogram = alpha.histogram()
            pixel_count = image.width * image.height
    except (OSError, UnidentifiedImageError) as error:
        add_error(errors, "decode_error", path, f"叶片图集无法解码：{error}")
        return None

    transparent = sum(histogram[:8]) / pixel_count
    opaque = sum(histogram[248:]) / pixel_count
    partial = sum(histogram[8:248]) / pixel_count

    if not 0.20 <= transparent <= 0.90:
        add_error(
            errors,
            "leaf_transparency",
            path,
            f"完全透明像素占比 {transparent:.4f}，要求 0.20~0.90",
        )
    if opaque < 0.08:
        add_error(
            errors,
            "leaf_opaque_area",
            path,
            f"完全不透明像素占比 {opaque:.4f}，最低要求 0.08",
        )
    if partial > 0.10:
        add_error(
            errors,
            "leaf_partial_alpha",
            path,
            f"半透明像素占比 {partial:.4f}，最高允许 0.10",
        )

    return {
        "transparent_ratio": round(transparent, 6),
        "opaque_ratio": round(opaque, 6),
        "partial_ratio": round(partial, 6),
    }


def validate_package(root: Path) -> dict[str, Any]:
    errors: list[dict[str, Any]] = []
    images: list[dict[str, Any]] = []

    for name, minimum_size in REFERENCE_SIZES.items():
        result = inspect_image(root / "references" / name, minimum_size, errors)
        if result:
            images.append(result)

    for name, minimum_size in TEXTURE_SIZES.items():
        result = inspect_image(root / "textures_source" / name, minimum_size, errors)
        if result:
            images.append(result)

    for relative_path in REQUIRED_DOCUMENTS:
        path = root / relative_path
        if not path.is_file():
            add_error(errors, "missing_file", path, "缺少必需文档")
        elif not path.read_text(encoding="utf-8").strip():
            add_error(errors, "empty_document", path, "文档不能为空")

    leaf_alpha = inspect_leaf_alpha(
        root / "textures_source" / "leaf_atlas_rgba.png", errors
    )
    total_bytes = sum(item["bytes"] for item in images)

    return {
        "pass": not errors,
        "root": root.as_posix(),
        "required_image_count": len(REFERENCE_SIZES) + len(TEXTURE_SIZES),
        "validated_image_count": len(images),
        "total_image_bytes": total_bytes,
        "leaf_alpha": leaf_alpha,
        "errors": errors,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="校验实时 3D 魔树美术资产包")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("assets/source/magic_tree"),
        help="魔树美术资产根目录",
    )
    parser.add_argument("--json", action="store_true", help="只输出 JSON")
    return parser.parse_args()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = parse_args()
    report = validate_package(args.root.resolve())

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        status = "通过" if report["pass"] else "未通过"
        print(f"魔树美术资产校验：{status}")
        print(
            f"图片：{report['validated_image_count']}/"
            f"{report['required_image_count']}，"
            f"总大小：{report['total_image_bytes'] / 1024 / 1024:.2f} MiB"
        )
        for error in report["errors"]:
            print(f"- [{error['code']}] {error['path']}: {error['message']}")

    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
