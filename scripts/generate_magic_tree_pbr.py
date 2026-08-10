from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source" / "magic_tree" / "textures_source"
OUTPUT = SOURCE / "pbr"
SIZE = 1024


def _normal_from_height(gray: np.ndarray, strength: float) -> Image.Image:
    height = gray.astype(np.float32) / 255.0
    dy, dx = np.gradient(height)
    normal = np.dstack((-dx * strength, -dy * strength, np.ones_like(height)))
    normal /= np.linalg.norm(normal, axis=2, keepdims=True).clip(min=1e-6)
    encoded = ((normal * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)
    return Image.fromarray(encoded, "RGB")


def _prepare_surface(name: str, source_name: str, strength: float) -> None:
    source = Image.open(SOURCE / source_name).convert("RGB")
    source = source.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    base = ImageEnhance.Contrast(source).enhance(1.08)
    base.save(OUTPUT / f"{name}_basecolor.png", optimize=True)

    gray = np.asarray(base.convert("L").filter(ImageFilter.GaussianBlur(0.8)))
    _normal_from_height(gray, strength).save(
        OUTPUT / f"{name}_normal.png", optimize=True
    )

    local = np.asarray(base.convert("L").filter(ImageFilter.GaussianBlur(6)))
    roughness = np.clip(218 - (gray.astype(np.int16) - local.astype(np.int16)), 120, 245)
    Image.fromarray(roughness.astype(np.uint8), "L").save(
        OUTPUT / f"{name}_roughness.png", optimize=True
    )

    ao = np.clip(235 - np.maximum(0, local.astype(np.int16) - gray.astype(np.int16)) * 2, 90, 255)
    Image.fromarray(ao.astype(np.uint8), "L").save(
        OUTPUT / f"{name}_ao.png", optimize=True
    )


def _prepare_leaf() -> None:
    leaf = Image.open(SOURCE / "leaf_atlas_rgba.png").convert("RGBA")
    leaf.thumbnail((SIZE, SIZE), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(leaf, ((SIZE - leaf.width) // 2, (SIZE - leaf.height) // 2))
    canvas.save(OUTPUT / "leaf_basecolor.png", optimize=True)

    single = Image.open(SOURCE / "leaf_atlas_rgba.png").convert("RGBA")
    single = single.crop((55, 15, 330, 390))
    single.thumbnail((460, 490), Image.Resampling.LANCZOS)
    single_canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    single_canvas.alpha_composite(
        single,
        ((512 - single.width) // 2, (512 - single.height) // 2),
    )
    single_canvas.save(OUTPUT / "leaf_single.png", optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    _prepare_surface("bark_old", "bark_old_basecolor_source.png", 6.0)
    _prepare_surface("soil", "soil_basecolor_source.png", 4.2)
    _prepare_leaf()
    print(f"魔树 PBR 源纹理已生成：{OUTPUT}")


if __name__ == "__main__":
    main()
